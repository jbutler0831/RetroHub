const { app, BrowserWindow, ipcMain, dialog, shell, Menu, nativeTheme } = require('electron');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');
const { SYSTEMS, MAKERS, EMULATORS } = require('./systems');
const { scanLibrary } = require('./library');
const { availableEmulators, resolve, readiness, launch } = require('./emulators');
const { coverPath } = require('./covers');

const RECENT_LIMIT = 24;

// ---- Settings ---------------------------------------------------------------

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
let settings = {
  libraryRoot: path.join(os.homedir(), 'Games'),
  favorites: [],
  lastPlayed: {},
  emulatorPaths: {},
};

function loadSettings() {
  try {
    settings = { ...settings, ...JSON.parse(fs.readFileSync(settingsFile(), 'utf8')) };
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
  };
}

let win;

function sendState() {
  win?.webContents.send('state', state());
}

async function play(id) {
  const game = gamesById.get(id);
  if (!game) return { error: 'That game is no longer in your library.' };
  try {
    await launch(game, settings.emulatorPaths);
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
  shell.openPath(system ? path.join(settings.libraryRoot, system.folder) : settings.libraryRoot);
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
    minWidth: 820,
    minHeight: 520,
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

app.whenReady().then(() => {
  loadSettings();
  rescan();
  createWindow();
});

app.on('window-all-closed', () => app.quit());
