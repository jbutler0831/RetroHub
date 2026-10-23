const { app, BrowserWindow, ipcMain, dialog, shell, Menu, nativeTheme } = require('electron');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');
const { SYSTEMS, MAKERS, EMULATORS } = require('./systems');
const { scanLibrary, systemDir } = require('./library');
const { availableEmulators, resolve, readiness, launch } = require('./emulators');
const { coverPath, knownMissing, lookAgain } = require('./covers');
const scanner = require('./scanner');
const playtime = require('./renderer/playtime');
const graphicsOptions = require('./graphics');

const RECENT_LIMIT = 24;
// `--console` starts full screen in couch mode, for devices that boot straight into RetroHub.
const consoleMode = process.argv.includes('--console');
// `--dev` (npm run dev) keeps its settings in .devdata/desktop and its games in .devdata/Games at
// the repository root, like the Mac app's RetroHub Dev, so a real library and settings are never
// touched. `--data-dir=<folder>` does the same in another folder (the window checks use a fresh one).
const dataDirArg = process.argv.find((arg) => arg.startsWith('--data-dir='));
const devData = dataDirArg ? path.resolve(dataDirArg.slice('--data-dir='.length))
  : process.argv.includes('--dev') ? path.join(__dirname, '../../.devdata') : null;
if (devData) app.setPath('userData', path.join(devData, 'desktop'));

// ---- Settings ---------------------------------------------------------------

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
let settings = {
  libraryRoot: devData ? path.join(devData, 'Games') : path.join(os.homedir(), 'Games'),
  favorites: [],
  lastPlayed: {},
  // { [game id]: { seconds, sessions } }, from sessions RetroHub started and saw end (renderer/playtime.js).
  playtime: {},
  emulatorPaths: {},
  graphics: { ...graphicsOptions.DEFAULTS },
  // 'system' (follow the OS), 'light' or 'dark': RetroHub's window only, never the OS setting.
  appearance: 'system',
};
const APPEARANCES = ['system', 'light', 'dark'];

function loadSettings() {
  try {
    const saved = JSON.parse(fs.readFileSync(settingsFile(), 'utf8'));
    settings = { ...settings, ...saved, graphics: { ...graphicsOptions.DEFAULTS, ...saved.graphics } };
  } catch { /* first launch */ }
}

function saveSettings() {
  fs.mkdirSync(path.dirname(settingsFile()), { recursive: true });
  fs.writeFileSync(settingsFile(), JSON.stringify(settings, null, 2));
}

// ---- Library state ----------------------------------------------------------

let games = {};
const gamesById = new Map();
const coversDir = () => path.join(app.getPath('userData'), 'covers');

// What the Smart Game Scanner has seen (src/scanner.js): the index of games, and when the user last
// reviewed the changes in Library Check. Kept apart from settings.json, which stays small.
const libraryFile = () => path.join(app.getPath('userData'), 'library.json');
let library = { index: null, reviewedAt: 0 };

function loadLibrary() {
  try {
    savedLibrary = fs.readFileSync(libraryFile(), 'utf8');
    library = { ...library, ...JSON.parse(savedLibrary) };
  } catch { /* first scan */ }
}

let savedLibrary = '';

/** Saves the index; RetroHub rescans each time its window comes forward, so only when it changed. */
function saveLibrary() {
  const json = JSON.stringify(library);
  if (json === savedLibrary) return;
  fs.mkdirSync(path.dirname(libraryFile()), { recursive: true });
  fs.writeFileSync(libraryFile(), json);
  savedLibrary = json;
}

function rescan() {
  games = scanLibrary(settings.libraryRoot);
  gamesById.clear();
  for (const list of Object.values(games)) for (const game of list) gamesById.set(game.id, game);
  const now = Date.now();
  // The first scan is the baseline: what's there already isn't news.
  if (!library.index) library.reviewedAt = now;
  library.index = scanner.updateIndex(library.index, games, { now });
  saveLibrary();
  fingerprintInBackground();
}

let fingerprinting = false;

/** Fingerprints new and changed files after the scan, a file at a time, then redraws. */
async function fingerprintInBackground() {
  if (fingerprinting) return;
  fingerprinting = true;
  let found = 0;
  try {
    for (const file of scanner.needsFingerprint(library.index)) {
      const entry = library.index[file];
      try {
        const fp = await scanner.fingerprint(file);
        // Only if the file is still the one indexed: a rescan may have replaced the entry.
        if (library.index[file] === entry) {
          entry.fp = fp;
          found++;
        }
      } catch { /* unreadable: matched on size only */ }
    }
  } finally {
    fingerprinting = false;
  }
  if (found) {
    saveLibrary();
    sendState();
  }
}

/** Library Check: the scanner's summary, with what each change affects. */
function libraryCheck() {
  const summary = scanner.summarize(library.index || {}, library.reviewedAt);
  const carries = (file) => ({ favorite: settings.favorites.includes(file), lastPlayed: settings.lastPlayed[file] || null,
                                playtime: settings.playtime[file]?.seconds || 0 });
  const noArt = [...gamesById.values()].filter((g) => knownMissing(g, coversDir()))
    .map((g) => ({ id: g.id, system: g.system, title: g.displayTitle }));
  return {
    reviewedAt: library.reviewedAt,
    added: summary.added,
    renamed: summary.renamed.map((r) => ({ ...r, ...carries(r.from) })),
    missing: summary.missing.map((m) => ({ ...m, ...carries(m.path) })),
    duplicates: summary.duplicates,
    noArt,
    // What the banner counts: news since the last review. Games still missing from before (an
    // unplugged drive, say) stay listed in Library Check without bringing the banner back.
    news: { added: summary.added.length, renamed: summary.renamed.length,
            missing: summary.missing.filter((m) => m.since > library.reviewedAt).length },
  };
}

/** Moves a game's favorite, play history and play time to its new path (a confirmed rename). */
function moveGameState(from, to) {
  settings.playtime = playtime.moveGame(settings.playtime, from, to);
  if (settings.favorites.includes(from)) {
    settings.favorites = [...new Set(settings.favorites.map((f) => (f === from ? to : f)))];
  }
  if (settings.lastPlayed[from]) {
    settings.lastPlayed[to] = Math.max(settings.lastPlayed[to] || 0, settings.lastPlayed[from]);
    delete settings.lastPlayed[from];
  }
}

/** Forgets a missing game: its index entry, favorite, play history and play time. */
function forgetGame(file) {
  delete library.index[file];
  delete settings.playtime[file];
  settings.favorites = settings.favorites.filter((f) => f !== file);
  delete settings.lastPlayed[file];
}

const LIBRARY_ACTIONS = {
  applyRename: ({ from, to }) => {
    if (!library.index[from]?.missingSince || !library.index[to] || library.index[to].missingSince) return;
    moveGameState(from, to);
    delete library.index[from];
  },
  notRenamed: ({ from }) => {
    if (library.index[from]?.missingSince) library.index[from].notRenamed = true;
  },
  removeMissing: ({ paths }) => {
    for (const file of paths) if (library.index[file]?.missingSince) forgetGame(file);
  },
  markReviewed: () => { library.reviewedAt = Date.now(); },
  lookAgain: ({ ids }) => {
    for (const id of ids) if (gamesById.has(id)) lookAgain(gamesById.get(id), coversDir());
  },
};

/** Everything the window needs to draw itself. */
function state() {
  const emulators = availableEmulators();
  return {
    platform: process.platform,
    consoleMode,
    libraryRoot: settings.libraryRoot,
    makers: MAKERS,
    systems: SYSTEMS.map(({ backends, ...info }) => ({ ...info, readiness: readiness({ backends, ...info }, settings.emulatorPaths) })),
    emulators: emulators.map((e) => {
      const found = resolve(e, settings.emulatorPaths);
      const covers = SYSTEMS.filter((s) => s.backends.some((b) => (b.type === 'app' ? b.emulator : b.type) === e.id));
      return { id: e.id, name: e.name, color: e.color, installed: !!found, location: found?.display || null,
               covers: covers.map((s) => s.folder).join(', ') };
    }),
    games,
    favorites: settings.favorites,
    lastPlayed: settings.lastPlayed,
    playtime: settings.playtime,
    recentLimit: RECENT_LIMIT,
    graphics: settings.graphics,
    appearance: settings.appearance,
    libraryCheck: libraryCheck(),
    shadersMissing: graphicsOptions.shadersMissing(resolve(EMULATORS.find((e) => e.id === 'retroarch'), settings.emulatorPaths),
                                                   settings.graphics),
  };
}

let win;
/** The game RetroHub started, while its emulator runs: { game, label, process, started }. */
let session = null;

/** Adds the session's time to the game's play time (sessions under 10 seconds don't count). */
function recordPlaytime(ended) {
  const seconds = (Date.now() - ended.started) / 1000;
  settings.playtime = playtime.addSession(settings.playtime, ended.game.id, seconds);
  saveSettings();
}

function sendState() {
  win?.webContents.send('state', state());
}

/** RetroHub comes back to the front when the game is closed, as the Mac app does. */
function gameEnded(child) {
  if (session?.process !== child) return;
  recordPlaytime(session);
  session = null;
  sendState();
  if (win && !win.isDestroyed()) {
    if (win.isMinimized()) win.restore();
    win.show();
    win.focus();
  }
}

async function play(id) {
  const game = gamesById.get(id);
  if (!game) return { error: 'That game is no longer in your library.' };
  // One game at a time: A pressed again while the emulator starts, or while it's open behind
  // RetroHub, mustn't start a second copy.
  if (session) return { error: `${session.label} is still running ${session.game.displayTitle}. Close it to start another game.` };
  try {
    // Console mode (a device that boots into RetroHub) always plays full screen.
    const fullscreen = consoleMode || settings.graphics.fullscreen !== false;
    const started = await launch(game, settings.emulatorPaths, settings.graphics, { fullscreen });
    if (started.process && started.process.exitCode === null) {
      session = { game, label: started.label, process: started.process, started: Date.now() };
      started.process.once('exit', () => gameEnded(started.process));
    }
    settings.lastPlayed[id] = Date.now();
    saveSettings();
    sendState();
    return { ok: true };
  } catch (error) {
    return { error: error.message };
  }
}

function toggleFavorite(id) {
  const set = new Set(settings.favorites);
  set.has(id) ? set.delete(id) : set.add(id);
  settings.favorites = [...set];
  saveSettings();
  sendState();
}

// ---- IPC --------------------------------------------------------------------

ipcMain.handle('state', () => state());
ipcMain.handle('rescan', () => { rescan(); return state(); });
ipcMain.handle('play', (_, id) => play(id));
ipcMain.handle('toggleFavorite', (_, id) => toggleFavorite(id));
ipcMain.handle('libraryAction', (_, action, details = {}) => {
  const run = LIBRARY_ACTIONS[action];
  if (run) {
    run(details);
    saveSettings();
    saveLibrary();
  }
  return state();
});

ipcMain.handle('setGraphics', (_, changes) => {
  const next = { ...settings.graphics, ...changes };
  if (['off', 'crt', 'smooth'].includes(next.filter) && [1, 2, 3, 4].includes(next.scale)) {
    settings.graphics = { filter: next.filter, scale: next.scale, widescreen: !!next.widescreen, fullscreen: next.fullscreen !== false };
    saveSettings();
  }
  return state();
});

ipcMain.handle('setAppearance', (_, appearance) => {
  if (APPEARANCES.includes(appearance)) {
    settings.appearance = appearance;
    nativeTheme.themeSource = appearance;
    saveSettings();
  }
  return state();
});

ipcMain.handle('cover', async (_, id) => {
  const game = gamesById.get(id);
  const file = game && (await coverPath(game, coversDir()));
  return file ? pathToFileURL(file).href : null;
});

ipcMain.handle('chooseRoot', async () => {
  const result = await dialog.showOpenDialog(win, {
    title: 'Choose Games Folder',
    message: 'RetroHub will create a folder for each system inside it.',
    defaultPath: settings.libraryRoot,
    properties: ['openDirectory', 'createDirectory'],
  });
  if (!result.canceled && result.filePaths[0]) {
    settings.libraryRoot = result.filePaths[0];
    saveSettings();
    rescan();
  }
  return state();
});

ipcMain.handle('locateEmulator', async (_, id) => {
  const emulator = EMULATORS.find((e) => e.id === id);
  if (!emulator) return state();
  const filters = process.platform === 'win32' ? [{ name: 'Programs', extensions: ['exe'] }] : [];
  const result = await dialog.showOpenDialog(win, {
    title: `Locate ${emulator.name}`,
    message: `Choose the ${emulator.name} program.`,
    properties: process.platform === 'darwin' ? ['openFile', 'treatPackageAsDirectory'] : ['openFile'],
    defaultPath: process.platform === 'darwin' ? '/Applications' : undefined,
    filters,
  });
  if (!result.canceled && result.filePaths[0]) {
    settings.emulatorPaths[id] = result.filePaths[0];
    saveSettings();
  }
  return state();
});

ipcMain.handle('openDownload', (_, id) => {
  const emulator = EMULATORS.find((e) => e.id === id);
  if (emulator) shell.openExternal(emulator.url);
});

ipcMain.handle('openFolder', (_, systemId) => {
  const system = SYSTEMS.find((s) => s.id === systemId);
  shell.openPath(system ? systemDir(settings.libraryRoot, system) : settings.libraryRoot);
});

// Only files RetroHub knows about, such as the copies Library Check lists as duplicates.
ipcMain.handle('showFile', (_, file) => {
  if (library.index?.[file] && !library.index[file].missingSince) shell.showItemInFolder(file);
});

ipcMain.handle('setFullScreen', (_, on) => win?.setFullScreen(!!on));

ipcMain.handle('gameMenu', (_, id) => {
  const game = gamesById.get(id);
  if (!game) return;
  const favorite = settings.favorites.includes(id);
  Menu.buildFromTemplate([
    { label: 'Play', click: async () => {
      const result = await play(id);
      if (result.error) win.webContents.send('error', result.error);
    } },
    { label: favorite ? 'Remove from Favorites' : 'Add to Favorites', click: () => toggleFavorite(id) },
    { type: 'separator' },
    { label: process.platform === 'darwin' ? 'Show in Finder' : 'Show in Folder', click: () => shell.showItemInFolder(game.bootPath) },
  ]).popup({ window: win });
});

// ---- Window -----------------------------------------------------------------

function createWindow() {
  win = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: consoleMode ? 320 : 820,
    minHeight: consoleMode ? 240 : 520,
    fullscreen: consoleMode,
    title: 'RetroHub',
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#1e1e20' : '#f5f5f7',
    icon: path.join(__dirname, 'renderer', 'icon.png'),
    autoHideMenuBar: true,
    show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
  });
  win.once('ready-to-show', () => win.show());
  win.on('focus', () => { rescan(); sendState(); });
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

if (process.platform !== 'darwin') Menu.setApplicationMenu(null);

// One RetroHub at a time: a second copy would also read the controller and overwrite the same
// settings file. Opening RetroHub again brings the open window forward instead.
const firstCopy = app.requestSingleInstanceLock();
if (!firstCopy) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!win) return;
    if (win.isMinimized()) win.restore();
    win.show();
    win.focus();
  });
}

app.whenReady().then(() => {
  if (!firstCopy) return;
  loadSettings();
  loadLibrary();
  // Before the window is created, so it opens in the chosen appearance without a flash.
  nativeTheme.themeSource = APPEARANCES.includes(settings.appearance) ? settings.appearance : 'system';
  rescan();
  createWindow();
});

app.on('window-all-closed', () => app.quit());
// Quitting RetroHub mid-game keeps the time played so far (the emulator itself keeps running).
app.on('before-quit', () => {
  if (session) recordPlaytime(session);
  session = null;
});
