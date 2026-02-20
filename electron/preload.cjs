const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('difffDesktop', {
  versions: {
    node: process.versions.node,
    chrome: process.versions.chrome,
    electron: process.versions.electron,
  },
});
