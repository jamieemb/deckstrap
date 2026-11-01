// Exposes the few window controls the installer page needs when it runs
// inside the Electron app. The page detects the app via the "app=electron"
// query parameter and only then shows its own title-bar buttons.
'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('deckstrapApp', {
  close: () => ipcRenderer.send('win:close'),
  minimize: () => ipcRenderer.send('win:minimize'),
  toggleMaximize: () => ipcRenderer.send('win:toggle-maximize'),
});
