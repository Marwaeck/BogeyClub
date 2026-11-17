// Bogey Club – Laufzeit für die Web-App im Browser (GitHub Pages, ohne Server).
// Bildet die Teile von window.claude nach, die die App nutzt: db und assets (im Browser gespeichert, IndexedDB),
// downloads (normaler Browser-Download) und sample (Scorekarte lesen mit ocr.js / Tesseract.js im Browser).
// Bilder liefert der Service Worker (sw.js) unter _blob/<id> aus derselben Datenbank aus.
(() => {
  if (window.claude?.use) return;           // in Claude läuft die echte Laufzeit
  window.BOGEY_BROWSER = true;

  // ---- IndexedDB: „docs“ (Schlüssel „coll/id“) und „blobs“ (Bilder) – dieselbe Datenbank nutzt sw.js ----
  const DB_NAME = "bogeyclub", DB_VERSION = 1;
  const openDB = () => new Promise((ok, no) => {
    const r = indexedDB.open(DB_NAME, DB_VERSION);
    r.onupgradeneeded = () => {
      const d = r.result;
      if (!d.objectStoreNames.contains("docs")) d.createObjectStore("docs");
      if (!d.objectStoreNames.contains("blobs")) d.createObjectStore("blobs");
    };
    r.onsuccess = () => ok(r.result);
    r.onerror = () => no(r.error);
  });
  const idb = openDB();
  async function tx(store, mode, fn) {
    const d = await idb;
    return new Promise((ok, no) => {
      const t = d.transaction(store, mode), s = t.objectStore(store);
      let result;
      Promise.resolve(fn(s)).then(r => { result = r; });
      t.oncomplete = () => ok(result);
      t.onerror = t.onabort = () => { const e = new Error(t.error?.name === "QuotaExceededError" ? "too_large" : "error"); e.code = e.message; no(e); };
    });
  }
  const req = r => new Promise((ok, no) => { r.onsuccess = () => ok(r.result); r.onerror = () => no(r.error); });

  // Browser bitten, die Daten nicht von selbst zu löschen, wenn der Speicher knapp wird
  navigator.storage?.persist?.().catch(() => { });

  // Service Worker: Bilder (_blob/…) und Offline-Betrieb
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(e => console.warn("Service Worker:", e));

  // ---- Datenbank: alles einmal laden, Änderungen sofort an alle Listener (auch in anderen Tabs) ----
  let data = {};   // { coll: { id: docData } }
  const listeners = new Map();   // coll -> Set(fn)
  const snapshot = coll => ({ docs: Object.entries(data[coll] || {}).map(([id, d]) => ({ id, data: () => JSON.parse(JSON.stringify(d)) })) });
  const notify = coll => (listeners.get(coll) || []).forEach(fn => { try { fn(snapshot(coll)); } catch (e) { console.error(e); } });
  async function loadAll() {
    const all = {};
    await tx("docs", "readonly", s => new Promise((ok, no) => {
      const c = s.openCursor();
      c.onsuccess = () => {
        const cur = c.result;
        if (!cur) return ok();
        const k = String(cur.key), i = k.indexOf("/");
        (all[k.slice(0, i)] ??= {})[k.slice(i + 1)] = cur.value;
        cur.continue();
      };
      c.onerror = () => no(c.error);
    }));
    data = all;
    return all;
  }
  let loaded = loadAll();
  const channel = "BroadcastChannel" in window ? new BroadcastChannel("bogeyclub") : null;
  if (channel) channel.onmessage = e => {
    loaded = loadAll().then(d => { if (e.data?.coll) notify(e.data.coll); else listeners.forEach((_, c) => notify(c)); return d; });
  };

  const db = {
    collection(coll) {
      return {
        onSnapshot(ok, err) {
          if (!listeners.has(coll)) listeners.set(coll, new Set());
          listeners.get(coll).add(ok);
          loaded.then(() => ok(snapshot(coll)), e => err && err(e));
          return () => listeners.get(coll).delete(ok);
        },
        doc(id) {
          const key = `${coll}/${id}`;
          return {
            async set(doc) {
              await loaded;
              const clean = JSON.parse(JSON.stringify(doc));
              await tx("docs", "readwrite", s => { s.put(clean, key); });
              (data[coll] ??= {})[id] = clean; notify(coll);
              channel?.postMessage({ coll });
            },
            async delete() {
              await loaded;
              await tx("docs", "readwrite", s => { s.delete(key); });
              if (data[coll]) delete data[coll][id];
              notify(coll);
              channel?.postMessage({ coll });
            },
            async get() {
              await loaded;
              const d = data[coll]?.[id];
              return { id, exists: !!d, data: () => d && JSON.parse(JSON.stringify(d)) };
            }
          };
        }
      };
    }
  };

  // ---- Bilder: in IndexedDB, ausgeliefert vom Service Worker unter _blob/<id> ----
  const newId = () => [...crypto.getRandomValues(new Uint8Array(16))].map(b => b.toString(16).padStart(2, "0")).join("");
  const assets = {
    async upload(blob) {
      if (blob.size > 8 * 1024 * 1024) { const e = new Error("too_large"); e.code = "too_large"; throw e; }
      if (!/^image\/(jpeg|png|webp|gif)$/.test(blob.type)) { const e = new Error("unsupported_type"); e.code = "unsupported_type"; throw e; }
      const id = newId();
      // Als ArrayBuffer speichern – Blobs in IndexedDB machen in manchen Safari-Versionen Probleme
      const buf = await blob.arrayBuffer();
      await tx("blobs", "readwrite", s => { s.put({ type: blob.type, data: buf }, id); });
      return { id, url: `_blob/${id}` };
    },
    async delete(id) { await tx("blobs", "readwrite", s => { s.delete(String(id)); }); }
  };

  // ---- Downloads: normaler Browser-Download ----
  const downloads = {
    async save({ filename, data }) {
      const blob = data instanceof Blob ? data : new Blob([data]);
      const url = URL.createObjectURL(blob);
      const a = Object.assign(document.createElement("a"), { href: url, download: filename || "download" });
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
    }
  };

  // ---- Scorekarte lesen: Texterkennung im Browser, Ergebnis im selben JSON-Format wie bei Claude ----
  window.BOGEY_SCAN_HINT = "Fotografiere die ausgefüllte Karte möglichst flach und vollständig oder wähle ein PDF, z. B. aus einer Golf-App. Die Texterkennung läuft direkt in deinem Browser (das Bild wird nicht hochgeladen) und liest Par, Lochvorgaben und Schlagzeilen. Gedruckte Karten und PDFs klappen am besten, Handschrift oft nicht – prüfe danach alles in der Karte. Zuverlässiger liest die iPhone- oder Mac-App mit Apples Texterkennung.";
  window.BOGEY_SCAN_BUSY = "Karte wird gelesen … beim ersten Mal lädt der Browser die Texterkennung, das kann etwa eine Minute dauern.";
  let ocrLoad = null;
  const sample = {
    async limits() { return { images: { maxCount: 3 } }; },
    async json(_prompt, opts = {}) {
      ocrLoad ??= new Promise((res, rej) => { const s = document.createElement("script"); s.src = "ocr.js"; s.onload = res; s.onerror = rej; document.head.appendChild(s); })
        .catch(e => { ocrLoad = null; throw e; });
      await ocrLoad;
      try { return await window.BogeyOCR.read(opts.images || []); }
      catch (e) { const err = new Error("image_rejected"); err.code = "image_rejected"; throw err; }
    }
  };

  // Installierte Web-App: per Doppelklick geöffnete .bogey-Dateien (File Handling API, Chrome/Edge)
  if ("launchQueue" in window) window.launchQueue.setConsumer(async params => {
    for (const h of params.files || []) {
      try { const f = await h.getFile(); (window.__bogeyOpenQueue = window.__bogeyOpenQueue || []).push([f.name, f]); } catch (e) { }
    }
  });

  window.claude = {
    async use(name) {
      if (name === "db") return db;
      if (name === "assets") return assets;
      if (name === "downloads") return downloads;
      if (name === "sample") return sample;
      return null;
    }
  };
})();
