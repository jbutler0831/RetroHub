const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('retrohub', {
  state: () => ipcRenderer.invoke('state'),
  rescan: () => ipcRenderer.invoke('rescan'),
  play: (id) => ipcRenderer.invoke('play', id),
  toggleFavorite: (id) => ipcRenderer.invoke('toggleFavorite', id),
  setGraphics: (changes) => ipcRenderer.invoke('setGraphics', changes),
  setAppearance: (appearance) => ipcRenderer.invoke('setAppearance', appearance),
  cover: (id) => ipcRenderer.invoke('cover', id),
  chooseRoot: () => ipcRenderer.invoke('chooseRoot'),
  locateEmulator: (id) => ipcRenderer.invoke('locateEmulator', id),
  openDownload: (id) => ipcRenderer.invoke('openDownload', id),
  openFolder: (systemId) => ipcRenderer.invoke('openFolder', systemId),
  setFullScreen: (on) => ipcRenderer.invoke('setFullScreen', on),
  gameMenu: (id) => ipcRenderer.invoke('gameMenu', id),
  onState: (callback) => ipcRenderer.on('state', (_, state) => callback(state)),
  onError: (callback) => ipcRenderer.on('error', (_, message) => callback(message)),
});
