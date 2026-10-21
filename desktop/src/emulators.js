// Finds installed emulators on macOS, Windows and Linux, and starts games in them.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { SYSTEMS, EMULATORS } = require('./systems');
const { exists } = require('./library');
const graphicsOptions = require('./graphics');

const platform = process.platform;
const home = os.homedir();

/** Emulators that exist on this OS (OpenEmu is Mac-only). */
function availableEmulators() {
  return EMULATORS.filter((e) => (platform === 'darwin' ? e.mac : platform === 'win32' ? e.win || e.scoop : e.linux || e.flatpak));
}

function expandEnv(p) {
  return p.replace(/%([^%]+)%/g, (_, name) => process.env[name] ?? process.env[name.toUpperCase()] ?? `%${name}%`);
}

function onPath(command) {
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    const full = path.join(dir, command);
    try {
      fs.accessSync(full, fs.constants.X_OK);
      return full;
    } catch { /* keep looking */ }
  }
  return null;
}

function flatpakInstalled(id) {
  return [path.join(home, '.local/share/flatpak/app', id), path.join('/var/lib/flatpak/app', id)].some(exists);
}

/** The executable inside a .app bundle, from its Info.plist. */
function macExecutable(appPath) {
  try {
    const plist = fs.readFileSync(path.join(appPath, 'Contents/Info.plist'), 'utf8');
    const name = plist.match(/<key>CFBundleExecutable<\/key>\s*<string>([^<]+)<\/string>/)?.[1];
    if (name) return path.join(appPath, 'Contents/MacOS', name);
  } catch { /* fall through */ }
  return null;
}

/**
 * How to run an emulator: { command, prefix, display, flatpak? } or null when it isn't installed.
 * A path the user picked in Setup always wins.
 */
function resolve(emulator, customPaths) {
  const custom = customPaths[emulator.id];
  if (custom && exists(custom)) {
    const command = custom.endsWith('.app') ? macExecutable(custom) : custom;
    if (command) return { command, prefix: [], display: custom, appPath: custom.endsWith('.app') ? custom : null };
  }
  if (platform === 'darwin') {
    for (const dir of ['/Applications', path.join(home, 'Applications')]) {
      for (const name of emulator.mac || []) {
        const appPath = path.join(dir, name);
        const command = exists(appPath) && macExecutable(appPath);
        if (command) return { command, prefix: [], display: appPath, appPath };
      }
    }
  } else if (platform === 'win32') {
    const candidates = (emulator.win || []).map(expandEnv);
    if (emulator.scoop) candidates.push(path.join(home, 'scoop/apps', emulator.scoop[0], 'current', emulator.scoop[1]));
    const found = candidates.find(exists);
    if (found) return { command: found, prefix: [], display: found };
  } else {
    for (const name of emulator.linux || []) {
      const found = onPath(name);
      if (found) return { command: found, prefix: [], display: found };
    }
    if (emulator.flatpak && flatpakInstalled(emulator.flatpak)) {
      return { command: 'flatpak', prefix: ['run', emulator.flatpak], display: `Flatpak (${emulator.flatpak})`, flatpak: true };
    }
  }
  return null;
}

/** Folders where RetroArch keeps its cores, for this install. */
function coreDirs(retroarch) {
  if (platform === 'darwin') return [path.join(home, 'Library/Application Support/RetroArch/cores')];
  if (platform === 'win32') return [path.join(path.dirname(retroarch.command), 'cores')];
  if (retroarch.flatpak) return [path.join(home, '.var/app/org.libretro.RetroArch/config/retroarch/cores')];
  return [path.join(home, '.config/retroarch/cores'), '/usr/lib/x86_64-linux-gnu/libretro', '/usr/lib/aarch64-linux-gnu/libretro', '/usr/lib/libretro', '/usr/lib64/libretro'];
}

const coreExt = platform === 'darwin' ? 'dylib' : platform === 'win32' ? 'dll' : 'so';

function run(command, args) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { detached: true, stdio: 'ignore' });
    child.once('error', reject);
    child.once('spawn', () => {
      child.unref();
      resolvePromise();
    });
  });
}

/** The first installed way to play a system: { label, start(gamePath) } or null. */
function plan(system, customPaths, graphics = graphicsOptions.DEFAULTS, { fullscreen = false } = {}) {
  for (const backend of system.backends) {
    if (backend.type === 'retroarch') {
      const retroarch = resolve(EMULATORS.find((e) => e.id === 'retroarch'), customPaths);
      if (!retroarch) continue;
      const dirs = coreDirs(retroarch);
      for (const core of backend.cores) {
        const corePath = dirs.map((d) => path.join(d, `${core.id}_libretro.${coreExt}`)).find(exists);
        if (corePath) {
          return {
            label: `RetroArch (${core.name})`,
            start: (game) => run(retroarch.command, [...retroarch.prefix, ...(fullscreen ? ['-f'] : []), '-L', corePath,
              ...graphicsOptions.retroArchArgs(system.id, core, retroarch, graphics), game]),
          };
        }
      }
    } else if (backend.type === 'openemu') {
      if (platform !== 'darwin') continue;
      const openemu = resolve(EMULATORS.find((e) => e.id === 'openemu'), customPaths);
      if (openemu) return { label: 'OpenEmu', start: (game) => run('open', ['-a', openemu.appPath, game]) };
    } else {
      const emulator = EMULATORS.find((e) => e.id === backend.emulator);
      const resolved = resolve(emulator, customPaths);
      if (resolved) {
        return { label: emulator.name, start: (game) => run(resolved.command, [...resolved.prefix, ...backend.args, game]) };
      }
    }
  }
  return null;
}

const listFormat = new Intl.ListFormat('en', { type: 'disjunction' });

/** Status for a system's header: { ready, summary, detail, missing }. */
function readiness(system, customPaths) {
  const found = plan(system, customPaths);
  if (found) return { ready: true, summary: `Plays with ${found.label}`, detail: system.note || null, missing: null };

  const usable = new Set(availableEmulators().map((e) => e.id));
  const backends = system.backends.filter((b) => usable.has(b.type === 'app' ? b.emulator : b.type));
  const retroarchBackend = backends.find((b) => b.type === 'retroarch');
  if (retroarchBackend && resolve(EMULATORS.find((e) => e.id === 'retroarch'), customPaths)) {
    const names = listFormat.format(retroarchBackend.cores.map((c) => c.name));
    return {
      ready: false, summary: 'Setup needed', missing: null,
      detail: `RetroArch needs the ${names} core. In RetroArch open Main Menu › Online Updater › Core Downloader and install it.`,
    };
  }
  const ids = backends.map((b) => (b.type === 'app' ? b.emulator : b.type));
  const names = listFormat.format(ids.map((id) => EMULATORS.find((e) => e.id === id).name));
  return { ready: false, summary: 'Setup needed', detail: `Install ${names} to play ${system.name} games.`, missing: ids[0] || null };
}

async function launch(game, customPaths, graphics, options) {
  const system = SYSTEMS.find((s) => s.id === game.system);
  const found = plan(system, customPaths, graphics, options);
  if (!found) throw new Error(readiness(system, customPaths).detail);
  try {
    await found.start(game.bootPath);
  } catch (error) {
    throw new Error(`Couldn't start ${found.label}: ${error.message}`);
  }
}

module.exports = { availableEmulators, resolve, readiness, launch };
