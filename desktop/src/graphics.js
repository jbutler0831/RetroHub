// Picture options RetroHub passes to RetroArch when it starts a game. Mirrors
// mac/Sources/RetroHub/Graphics.swift. RetroArch's own settings are left alone: the options only
// apply to games RetroHub launches.
const fs = require('fs');
const os = require('os');
const path = require('path');

const home = os.homedir();

/** Shader presets, relative to RetroArch's shaders folder and without the .slangp/.glslp extension. */
const FILTERS = {
  off: null,
  crt: 'crt/crt-geom',
  smooth: 'edge-smoothing/xbrz/xbrz-freescale-multipass',
};

const DEFAULTS = { filter: 'off', scale: 1, widescreen: false };

/** 2D systems the screen filter applies to, and 3D systems that get resolution and widescreen options. */
const FILTER_SYSTEMS = ['nes', 'snes', 'gb', 'gbc', 'gba', 'genesis', 'mastersystem', 'gamegear', 'segacd', 'sega32x',
                        'saturn', 'pce', 'neogeo', 'atari2600', 'arcade'];
const ENHANCED_SYSTEMS = ['n64', 'ps1', 'dreamcast'];

/** RetroArch's base folder and main config file for an install found by emulators.resolve(). */
function retroArchPaths(retroarch) {
  let base;
  if (process.platform === 'darwin') base = path.join(home, 'Library/Application Support/RetroArch');
  else if (process.platform === 'win32') base = path.dirname(retroarch.command);
  else if (retroarch.flatpak) base = path.join(home, '.var/app/org.libretro.RetroArch/config/retroarch');
  else base = path.join(process.env.XDG_CONFIG_HOME || path.join(home, '.config'), 'retroarch');
  const configFile = process.platform === 'darwin' ? path.join(base, 'config/retroarch.cfg') : path.join(base, 'retroarch.cfg');
  return { base, configFile };
}

/** `key = "value"` lines from a RetroArch config file. */
function readConfig(file) {
  const values = {};
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch { return values; }
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*([^=\s]+)\s*=\s*"?(.*?)"?\s*$/);
    if (match) values[match[1]] = match[2];
  }
  return values;
}

/** A folder setting from retroarch.cfg, or RetroArch's default inside its base folder. */
function directory(setting, base, name) {
  if (!setting || setting === 'default') return path.join(base, name);
  if (setting.startsWith('~')) return path.join(home, setting.slice(1));
  if (setting.startsWith(':')) return path.join(base, setting.slice(1));
  return setting;
}

/** The preset file for a filter, or null when the filter is off or RetroArch's shaders aren't downloaded. */
function shaderPath(filter, base, config) {
  const preset = FILTERS[filter];
  if (!preset) return null;
  // The legacy "gl" driver only runs GLSL shaders; Vulkan, glcore, Metal and Direct3D run Slang.
  const [folder, ext] = config.video_driver === 'gl' ? ['shaders_glsl', 'glslp'] : ['shaders_slang', 'slangp'];
  const file = path.join(directory(config.video_shader_dir, base, 'shaders'), folder, `${preset}.${ext}`);
  return fs.existsSync(file) ? file : null;
}

/**
 * Core options that raise the internal resolution and turn on widescreen hacks.
 * Values are the ones each core lists for these options.
 */
function coreOptions(coreId, scale, widescreen) {
  // Some cores only offer powers of two.
  const power = scale >= 4 ? 4 : scale >= 2 ? 2 : 1;
  const options = {};
  switch (coreId) {
    case 'mupen64plus_next':
      if (scale > 1) {
        options['mupen64plus-EnableNativeResFactor'] = String(scale);
        options['mupen64plus-parallel-rdp-upscaling'] = `${power}x`;
      }
      if (widescreen) options['mupen64plus-aspect'] = '16:9 adjusted';
      break;
    case 'parallel_n64':
      if (scale > 1) options['parallel-n64-upscaling'] = `${power}x`;
      if (widescreen) options['parallel-n64-aspectratiohint'] = 'widescreen';
      break;
    case 'swanstation':
      if (scale > 1) options.swanstation_GPU_ResolutionScale = String(scale);
      if (widescreen) {
        options.swanstation_GPU_WidescreenHack = 'true';
        options.swanstation_Display_AspectRatio = '16:9';
      }
      break;
    case 'flycast':
      // Dreamcast renders at 640x480; these are its 2x, 3x and 4x sizes.
      if (scale > 1) options.reicast_internal_resolution = `${640 * scale}x${480 * scale}`;
      if (widescreen) {
        options.reicast_widescreen_hack = 'enabled';
        options.reicast_widescreen_cheats = 'enabled';
      }
      break;
    case 'mednafen_psx':
      if (scale > 1) options.beetle_psx_internal_resolution = `${power}x`;
      if (widescreen) {
        options.beetle_psx_widescreen_hack = 'enabled';
        options.beetle_psx_widescreen_hack_aspect_ratio = '16:9';
      }
      break;
  }
  return options;
}

/** Writes a copy of the core's current options with `overrides` applied and returns its path. */
function writeCoreOptions(core, overrides, configDir) {
  const read = (file) => { try { return fs.readFileSync(file, 'utf8'); } catch { return null; } };
  const current = read(path.join(configDir, core.name, `${core.name}.opt`))
    ?? read(path.join(configDir, 'retroarch-core-options.cfg')) ?? '';
  const keys = Object.keys(overrides);
  const lines = current.split(/\r?\n/).filter((line) => line && !keys.some((key) => line.startsWith(`${key} =`)));
  for (const key of keys.sort()) lines.push(`${key} = "${overrides[key]}"`);
  const file = path.join(configDir, 'RetroHub', `${core.id}.opt`);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${lines.join('\n')}\n`);
  return file;
}

/** Extra RetroArch arguments for the current graphics settings. */
function retroArchArgs(systemId, core, retroarch, graphics) {
  const { base, configFile } = retroArchPaths(retroarch);
  const config = readConfig(configFile);
  const configDir = directory(config.rgui_config_directory, base, 'config');
  const args = [];
  // Settings for this run only; not saving on exit keeps them out of the user's retroarch.cfg.
  const settings = [];
  const shader = FILTER_SYSTEMS.includes(systemId) && shaderPath(graphics.filter, base, config);
  if (shader) {
    args.push(`--set-shader=${shader}`);
    settings.push('video_shader_enable = "true"');
  }
  const overrides = ENHANCED_SYSTEMS.includes(systemId) ? coreOptions(core.id, graphics.scale, graphics.widescreen) : {};
  if (Object.keys(overrides).length) {
    try {
      const options = writeCoreOptions(core, overrides, configDir);
      settings.push('global_core_options = "true"', `core_options_path = "${options}"`);
    } catch { /* play without them */ }
  }
  if (!settings.length) return args;
  settings.push('config_save_on_exit = "false"');
  try {
    const file = path.join(configDir, 'RetroHub', `${core.id}.cfg`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `${settings.join('\n')}\n`);
    args.push(`--appendconfig=${file}`);
  } catch { /* play without them */ }
  return args;
}

/** Whether RetroArch's shaders need downloading before the chosen filter can work. */
function shadersMissing(retroarch, graphics) {
  if (!retroarch || !FILTERS[graphics.filter]) return false;
  const { base, configFile } = retroArchPaths(retroarch);
  return !shaderPath(graphics.filter, base, readConfig(configFile));
}

module.exports = { DEFAULTS, retroArchArgs, shadersMissing, coreOptions };
