// Datenablage der Windows-App – gleiches Format wie die Mac-App (mac/Sources/BogeyCore/Store.swift):
// alle Collections in daten.json, Bilder einzeln im Unterordner „Bilder“, einmal pro Tag vor der ersten
// Änderung eine Kopie unter „Sicherungen“ (die letzten 30). Ordner: %APPDATA%\Bogey Club
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const EXT = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif" };
const TYPE = Object.fromEntries(Object.entries(EXT).map(([t, e]) => [e, t]));
const validId = id => typeof id === "string" && id.length >= 1 && id.length <= 200 && id !== "." && id !== ".." && /^[A-Za-z0-9_\-.~:@+]+$/.test(id);

class Store {
  constructor(folder) {
    this.folder = folder;
    this.dataFile = path.join(folder, "daten.json");
    this.photos = path.join(folder, "Bilder");
    this.backups = path.join(folder, "Sicherungen");
    this.backedUpToday = false;
    fs.mkdirSync(this.photos, { recursive: true });
    this.data = {};
    if (fs.existsSync(this.dataFile)) {
      const obj = JSON.parse(fs.readFileSync(this.dataFile, "utf8"));   // wirft bei beschädigter Datei
      for (const [coll, docs] of Object.entries(obj)) if (docs && typeof docs === "object") this.data[coll] = docs;
    }
  }

  allJSON() { return JSON.stringify(this.data); }

  set(coll, id, json) {
    if (!validId(coll) || !validId(id)) throw Object.assign(new Error("bad_id"), { code: "error" });
    const doc = JSON.parse(json);
    if (!doc || typeof doc !== "object" || Array.isArray(doc)) throw Object.assign(new Error("bad_data"), { code: "error" });
    (this.data[coll] ??= {})[id] = doc;
    this.persist();
  }

  delete(coll, id) {
    if (!this.data[coll] || !(id in this.data[coll])) return;
    delete this.data[coll][id];
    this.persist();
  }

  persist() {
    this.backupOncePerDay();
    const sorted = Object.fromEntries(Object.keys(this.data).sort().map(c =>
      [c, Object.fromEntries(Object.keys(this.data[c]).sort().map(id => [id, this.data[c][id]]))]));
    const tmp = this.dataFile + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(sorted, null, 2));
    fs.renameSync(tmp, this.dataFile);   // atomar ersetzen
  }

  backupOncePerDay() {
    if (this.backedUpToday || !fs.existsSync(this.dataFile)) return;
    this.backedUpToday = true;
    try {
      fs.mkdirSync(this.backups, { recursive: true });
      const d = new Date(), day = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
      const target = path.join(this.backups, `daten-${day}.json`);
      if (!fs.existsSync(target)) fs.copyFileSync(this.dataFile, target);
      const files = fs.readdirSync(this.backups).filter(f => f.startsWith("daten-")).sort();
      for (const f of files.slice(0, Math.max(0, files.length - 30))) fs.rmSync(path.join(this.backups, f), { force: true });
    } catch (e) { /* Sicherung ist ein Extra – Speichern geht trotzdem weiter */ }
  }

  addPhoto(bytes, type) {
    const ext = EXT[type];
    if (!ext) throw Object.assign(new Error("unsupported_type"), { code: "unsupported_type" });
    const id = crypto.randomBytes(16).toString("hex");
    fs.writeFileSync(path.join(this.photos, `${id}.${ext}`), bytes);
    return id;
  }

  photo(id) {
    if (!validId(id)) return null;
    for (const [ext, type] of Object.entries(TYPE)) {
      const file = path.join(this.photos, `${id}.${ext}`);
      if (fs.existsSync(file)) return { file, type };
    }
    return null;
  }

  deletePhoto(id) { const p = this.photo(id); if (p) fs.rmSync(p.file, { force: true }); }
}

module.exports = { Store, validId };
