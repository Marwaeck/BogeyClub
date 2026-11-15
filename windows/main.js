// Bogey Club für Windows: die Bogey-Club-Oberfläche in einem eigenen Fenster, ohne Claude.
// Daten und Bilder liegen auf dem PC (%APPDATA%\Bogey Club), Scorekarten liest die mitgelieferte
// Texterkennung (Tesseract) offline. Aufbau wie die Mac-App: Seiten unter bogey://app/…,
// Bilder unter bogey://app/_blob/<id>, Befehle der Oberfläche über preload.js.
const { app, BrowserWindow, Menu, dialog, ipcMain, protocol, shell } = require("electron");
const fs = require("node:fs");
const path = require("node:path");
const { Store } = require("./store");

app.setName("Bogey Club");
app.setAppUserModelId("club.bogey.windows");
protocol.registerSchemesAsPrivileged([
  { scheme: "bogey", privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } }
]);

const WEB = process.env.BOGEY_WEB_DIR || path.join(__dirname, "build", "web");
const DATA = process.env.BOGEY_DATA_DIR || path.join(app.getPath("appData"), "Bogey Club");
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".json": "application/json",
  ".wasm": "application/wasm", ".gz": "application/gzip" };

let store, win;

function serve(request) {
  const url = new URL(request.url);
  let p = decodeURIComponent(url.pathname);
  if (p === "/" || !p) p = "/index.html";
  let file = null, type = "application/octet-stream";
  if (p.startsWith("/_blob/")) {
    const ph = store.photo(p.slice(7));
    if (ph) { file = ph.file; type = ph.type; }
  } else {
    const candidate = path.normalize(path.join(WEB, p));
    if (candidate.startsWith(path.normalize(WEB + path.sep))) { file = candidate; type = MIME[path.extname(candidate).toLowerCase()] || type; }
  }
  if (!file || !fs.existsSync(file) || !fs.statSync(file).isFile()) return new Response("Not found", { status: 404, headers: { "content-type": "text/plain" } });
  const body = request.method === "HEAD" ? null : fs.readFileSync(file);
  return new Response(body, { status: 200, headers: { "content-type": type, "content-length": String(fs.statSync(file).size), "cache-control": "no-store" } });
}

async function handle(_e, msg) {
  const s = k => (typeof msg?.[k] === "string" ? msg[k] : "");
  try {
    switch (msg?.cmd) {
      case "db.load": return store.allJSON();
      case "db.set": store.set(s("coll"), s("id"), s("data")); return {};
      case "db.delete": store.delete(s("coll"), s("id")); return {};
      case "assets.upload": {
        const id = store.addPhoto(Buffer.from(s("base64"), "base64"), s("type"));
        return { id, url: `/_blob/${id}` };
      }
      case "assets.delete": store.deletePhoto(s("id")); return {};
      case "download.save": {
        const name = s("filename") || "download";
        const ext = path.extname(name).slice(1);
        const r = await dialog.showSaveDialog(win, {
          defaultPath: path.join(app.getPath("downloads"), name),
          filters: ext ? [{ name: ext.toUpperCase(), extensions: [ext] }] : []
        });
        if (r.canceled || !r.filePath) return { error: "declined" };
        fs.writeFileSync(r.filePath, Buffer.from(s("base64"), "base64"));
        return {};
      }
      default: return { error: "unknown_command" };
    }
  } catch (e) {
    console.error(e);
    return { error: e?.code || "error" };
  }
}

function buildMenu() {
  const template = [
    { label: "Datei", submenu: [
      { label: "Datenordner öffnen", click: () => shell.openPath(DATA) },
      { type: "separator" },
      { role: "quit", label: "Beenden" }
    ] },
    { label: "Bearbeiten", submenu: [
      { role: "undo", label: "Rückgängig" }, { role: "redo", label: "Wiederholen" }, { type: "separator" },
      { role: "cut", label: "Ausschneiden" }, { role: "copy", label: "Kopieren" }, { role: "paste", label: "Einfügen" },
      { role: "selectAll", label: "Alles auswählen" }
    ] },
    { label: "Ansicht", submenu: [
      { label: "Neu laden", accelerator: "CmdOrCtrl+R", click: () => win?.loadURL("bogey://app/index.html") },
      { type: "separator" },
      { role: "resetZoom", label: "Originalgröße" }, { role: "zoomIn", label: "Vergrößern" }, { role: "zoomOut", label: "Verkleinern" },
      { type: "separator" },
      { role: "togglefullscreen", label: "Vollbild" }
    ] },
    { label: "Hilfe", submenu: [
      { label: "Über Bogey Club", click: () => dialog.showMessageBox(win, {
        type: "info", title: "Bogey Club", message: `Bogey Club ${app.getVersion()}`,
        detail: "Privates Golf-Scorebuch.\nDaten liegen auf diesem PC:\n" + DATA + "\n\nKartendaten © OpenStreetMap-Mitwirkende, ODbL. Texterkennung: Tesseract (Apache 2.0)."
      }) }
    ] }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  const statePath = path.join(DATA, "fenster.json");
  let bounds = { width: 1180, height: 860 };
  try { bounds = { ...bounds, ...JSON.parse(fs.readFileSync(statePath, "utf8")) }; } catch (e) { }
  win = new BrowserWindow({
    ...bounds, minWidth: 420, minHeight: 520, title: "Bogey Club", backgroundColor: "#eef3ef", show: false,
    icon: path.join(__dirname, "build", "icon.png"),
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: false }
  });
  win.once("ready-to-show", () => win.show());
  win.on("close", () => { try { fs.writeFileSync(statePath, JSON.stringify(win.getBounds())); } catch (e) { } });
  // Externe Links (Apple Karten, Google Maps …) im Standard-Browser öffnen
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^(https?|mailto):/.test(url)) shell.openExternal(url); return { action: "deny" }; });
  win.webContents.on("will-navigate", (e, url) => { if (!url.startsWith("bogey://")) { e.preventDefault(); if (/^(https?|mailto):/.test(url)) shell.openExternal(url); } });
  win.webContents.on("render-process-gone", () => win.loadURL("bogey://app/index.html"));
  win.loadURL("bogey://app/index.html");
}

if (!app.requestSingleInstanceLock()) app.quit();
app.on("second-instance", () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });

app.whenReady().then(() => {
  try {
    store = new Store(DATA);
  } catch (e) {
    const choice = dialog.showMessageBoxSync({
      type: "error", title: "Bogey Club", message: "Die Bogey-Club-Daten konnten nicht geöffnet werden.",
      detail: `Die Datei „daten.json“ im Datenordner ist beschädigt. Im Unterordner „Sicherungen“ liegen tägliche Kopien.\n${DATA}`,
      buttons: ["Datenordner öffnen", "Beenden"]
    });
    if (choice === 0) shell.openPath(DATA);
    app.quit();
    return;
  }
  protocol.handle("bogey", serve);
  ipcMain.handle("bogey", handle);
  buildMenu();
  createWindow();
});

app.on("window-all-closed", () => app.quit());
