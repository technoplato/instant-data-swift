const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("exerciseGem", {
  start: () => ipcRenderer.invoke("gem-start"),
  stop: () => ipcRenderer.invoke("gem-stop"),
  onEvent: (cb) => {
    const handler = (_event, row) => cb(row);
    ipcRenderer.on("gem-event", handler);
    return () => ipcRenderer.removeListener("gem-event", handler);
  },
});
