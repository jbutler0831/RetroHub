const { app, BrowserWindow, ipcMain, dialog, shell, Menu, nativeTheme } = require('electron');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');
const { SYSTEMS, MAKERS, EMULATORS } = require('./systems');
const { scanLibrary, systemDir } = require('./library');
const { availableEmulators, resolve, readiness, launch } = require('./emulators');
const { coverPath } = require('./covers');
const graphicsOptions = require('./graphics');

const RECENT_LIMIT = 24;
// `--console` starts full screen in couch mode, for devices that boot straight into RetroHub.
const consoleMode = process.argv.includes('--console');
// `--dev` (npm run dev) keeps its settings in .devdata/desktop and its games in .devdata/Games at
// the repository root, like the Mac app's RetroHub Dev, so a real library and settings are never
// touched.
const devData = process.argv.includes('--dev') ? path.join(__dirname, '../../.devdata') : null;
if (devData) app.setPath('userData', path.join(devData, 'desktop'));

// ---- Settings ---------------------------------------------------------------

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
let settings = {
  libraryRoot: devData ? path.join(devData, 'Games') : path.join(os.homedir(), 'Games'),
  favorites: [],
  lastPlayed: {},
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

function rescan() {
  games = scanLibrary(settings.libraryRoot);
  gamesById.clear();
  for (const list of Object.values(games)) for (const game of list) gamesById.set(game.id, game);
}

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
    recentLimit: RECENT_LIMIT,
    graphics: settings.graphics,
    appearance: settings.appearance,
    shadersMissing: graphicsOptions.shadersMissing(resolve(EMULATORS.find((e) => e.id === 'retroarch'), settings.emulatorPaths),
                                                   settings.graphics),
  };
}

let win;
/** The game RetroHub started, while its emulator runs: { game, label, process }. */
let session = null;

function sendState() {
  win?.webContents.send('state', state());
}

/** RetroHub comes back to the front when the game is closed, as the Mac app does. */
function gameEnded(child) {
  if (session?.process !== child) return;
  session = null;
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
    const started = await launch(game, settings.emulatorPaths, settings.graphics, { fullscreen: consoleMode });
    if (started.process && started.process.exitCode === null) {
      session = { game, label: started.label, process: started.process };
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

ipcMain.handle('setGraphics', (_, changes) => {
  const next = { ...settings.graphics, ...changes };
  if (['off', 'crt', 'smooth'].includes(next.filter) && [1, 2, 3, 4].includes(next.scale)) {
    settings.graphics = { filter: next.filter, scale: next.scale, widescreen: !!next.widescreen };
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
  const file = game && (await coverPath(game, path.join(app.getPath('userData'), 'covers')));
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
  // Before the window is created, so it opens in the chosen appearance without a flash.
  nativeTheme.themeSource = APPEARANCES.includes(settings.appearance) ? settings.appearance : 'system';
  rescan();
  createWindow();
});

app.on('window-all-closed', () => app.quit());
