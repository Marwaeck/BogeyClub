// Verbindet die Oberfläche (mac/runtime.js) mit dem Hauptprozess – dieselben Befehle wie die Mac-App.
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("bogeyNative", {
  platform: "windows",
  postMessage: msg => ipcRenderer.invoke("bogey", msg)
});
