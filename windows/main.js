// Bogey Club für Windows: die Bogey-Club-Oberfläche in einem eigenen Fenster, ohne Claude.
// Daten und Bilder liegen auf dem PC (%APPDATA%\Bogey Club), Scorekarten liest die mitgelieferte
// Texterkennung (Tesseract) offline. Aufbau wie die Mac-App: Seiten unter bogey://app/…,
// Bilder unter bogey://app/_blob/<id>, Befehle der Oberfläche über preload.js.
const { app, BrowserWindow, Menu, dialog, ipcMain, protocol, shell, net } = require("electron");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFile, spawn } = require("node:child_process");
const { Store } = require("./store");
const updater = require("./updater");

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

// ---------- Einstellungen (Updater) ----------
const settingsPath = () => path.join(DATA, "einstellungen.json");
function settings() { try { return JSON.parse(fs.readFileSync(settingsPath(), "utf8")); } catch (e) { return {}; } }
function saveSettings(patch) { try { fs.writeFileSync(settingsPath(), JSON.stringify({ ...settings(), ...patch }, null, 2)); } catch (e) { } }
const autoUpdate = () => settings().updateAutomatic !== false;

// ---------- Lizenz ----------
const LEGAL = app.isPackaged ? path.join(process.resourcesPath, "Lizenzen") : path.join(__dirname, "..", "licenses");
const LICENSE_FILE = app.isPackaged ? path.join(LEGAL, "LICENSE.txt") : path.join(__dirname, "..", "LICENSE");

// ---------- Updater: GitHub-Releases ----------
let checking = false;
async function checkForUpdates(interactive) {
  if (checking) return;
  checking = true;
  saveSettings({ updateLastCheck: Date.now() });
  const info = (message, detail) => interactive && dialog.showMessageBox(win, { type: "info", title: "Bogey Club", message, detail });
  try {
    let release;
    try {
      const r = await net.fetch(updater.LATEST_URL, { headers: { accept: "application/vnd.github+json", "user-agent": `BogeyClub-Windows/${app.getVersion()}` } });
      if (r.status === 404) { info("Du hast die neueste Version.", `Bogey Club ${app.getVersion()} – auf GitHub ist noch keine neuere Version veröffentlicht.`); return; }
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      release = updater.parseRelease(await r.text());
    } catch (e) {
      info("Keine Verbindung zu GitHub.", "Die Suche nach Updates braucht Internet. Bitte später erneut versuchen.");
      return;
    }
    if (!updater.isNewer(release.version, app.getVersion())) { info("Du hast die neueste Version.", `Bogey Club ${app.getVersion()} ist aktuell.`); return; }
    if (!interactive && settings().updateSkip === release.version) return;

    const canInstall = !!release.assetURL && app.isPackaged && process.platform === "win32";
    const { response } = await dialog.showMessageBox(win, {
      type: "info", title: "Update verfügbar", message: `Bogey Club ${release.version} ist verfügbar`,
      detail: `Installiert ist ${app.getVersion()}. Deine Spieler, Plätze und Runden bleiben erhalten.` + (release.notes ? `\n\nNeu:\n${release.notes.slice(0, 700)}` : ""),
      buttons: [canInstall ? "Jetzt installieren" : "Download-Seite öffnen", "Später", "Diese Version überspringen"], defaultId: 0, cancelId: 1
    });
    if (response === 2) saveSettings({ updateSkip: release.version });
    if (response !== 0) return;
    if (!canInstall) { shell.openExternal(release.pageURL); return; }
    await installUpdate(release);
  } finally { checking = false; }
}

// Neue Version laden, entpacken und nach dem Beenden über den App-Ordner kopieren (siehe updater.installScript)
async function installUpdate(release) {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "bogey-update-"));
  const zip = path.join(work, "update.zip"), unpacked = path.join(work, "neu");
  try {
    win?.setProgressBar(2);   // unbestimmter Fortschritt in der Taskleiste
    const r = await net.fetch(release.assetURL);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    fs.writeFileSync(zip, Buffer.from(await r.arrayBuffer()));
    fs.mkdirSync(unpacked);
    // tar.exe gehört ab Windows 10 zum System und kann ZIP-Dateien entpacken
    await new Promise((ok, no) => execFile("tar", ["-xf", zip, "-C", unpacked], { windowsHide: true }, e => e ? no(e) : ok()));
    if (!fs.existsSync(path.join(unpacked, "Bogey Club.exe"))) throw new Error("ZIP ohne Bogey Club.exe");
    const script = path.join(work, "update.cmd");
    fs.writeFileSync(script, updater.installScript({ pid: process.pid, source: unpacked, target: path.dirname(process.execPath), page: release.pageURL }));
    spawn("cmd.exe", ["/c", script], { detached: true, stdio: "ignore", windowsHide: true }).unref();
    app.quit();
  } catch (e) {
    console.error(e);
    win?.setProgressBar(-1);
    const { response } = await dialog.showMessageBox(win, {
      type: "warning", title: "Bogey Club", message: "Das Update konnte nicht installiert werden.",
      detail: "Lade die neue Version bitte von der Download-Seite, entpacke sie und ersetze den alten Bogey-Club-Ordner. Deine Daten bleiben dabei erhalten.",
      buttons: ["Download-Seite öffnen", "Abbrechen"]
    });
    if (response === 0) shell.openExternal(release.pageURL);
  }
}

function buildMenu() {
  const template = [
    { label: "Datei", submenu: [
      { label: "Bogey-Datei öffnen …", accelerator: "CmdOrCtrl+O", click: () => chooseFile() },
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
      { label: "Nach Updates suchen …", click: () => checkForUpdates(true) },
      { label: "Automatisch nach Updates suchen", type: "checkbox", checked: autoUpdate(), click: item => saveSettings({ updateAutomatic: item.checked }) },
      { type: "separator" },
      { label: "Lizenz …", click: () => shell.openPath(LICENSE_FILE) },
      { label: "Lizenzen der Bausteine …", click: () => shell.openPath(LEGAL) },
      { type: "separator" },
      { label: "Über Bogey Club", click: () => dialog.showMessageBox(win, {
        type: "info", title: "Bogey Club", message: `Bogey Club ${app.getVersion()}`,
        detail: "Privates Golf-Scorebuch.\n© 2026 Marwaeck. Alle Rechte vorbehalten – private Nutzung kostenlos.\n\nDaten liegen auf diesem PC:\n" + DATA +
          "\n\nKartendaten © OpenStreetMap-Mitwirkende, ODbL. Texterkennung: Tesseract (Apache 2.0). Lizenzen: Hilfe → Lizenzen der Bausteine."
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
  win.webContents.on("did-finish-load", () => { pageReady = true; sendFiles(); });
  win.webContents.on("did-start-loading", () => { pageReady = false; });
  win.webContents.on("render-process-gone", () => win.loadURL("bogey://app/index.html"));
  win.loadURL("bogey://app/index.html");
}

// ---- Bogey-Dateien öffnen (Doppelklick im Explorer, „Öffnen mit“, Datei → Öffnen) ----
const openArgs = argv => argv.slice(1).filter(a => /\.(bogey|json)$/i.test(a) && fs.existsSync(a));
let pendingFiles = openArgs(process.argv), pageReady = false;
function sendFiles() {
  if (!win || !pageReady) return;
  const files = pendingFiles; pendingFiles = [];
  for (const f of files) {
    try {
      const name = JSON.stringify(path.basename(f)), b64 = fs.readFileSync(f).toString("base64");
      win.webContents.executeJavaScript(`(window.bogeyOpenFile ? window.bogeyOpenFile(${name}, "${b64}") : (window.__bogeyOpenQueue = window.__bogeyOpenQueue || []).push([${name}, "${b64}"]))`).catch(() => { });
    } catch (e) { }
  }
}
function openFiles(files) { pendingFiles.push(...files); sendFiles(); }
async function chooseFile() {
  const r = await dialog.showOpenDialog(win, { title: "Bogey-Datei öffnen", properties: ["openFile"],
    filters: [{ name: "Bogey-Club-Dateien", extensions: ["bogey", "json"] }] });
  if (!r.canceled && r.filePaths[0]) openFiles([r.filePaths[0]]);
}

if (!app.requestSingleInstanceLock()) app.quit();
app.on("second-instance", (_e, argv) => {
  if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
  openFiles(openArgs(argv));
});

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
  // Still nach Updates suchen – höchstens einmal am Tag, nur in der fertigen App
  if (app.isPackaged && autoUpdate() && Date.now() - (settings().updateLastCheck || 0) > 24 * 3600 * 1000) {
    setTimeout(() => checkForUpdates(false), 4000);
  }
});

app.on("window-all-closed", () => app.quit());
