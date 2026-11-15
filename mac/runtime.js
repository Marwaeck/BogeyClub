// Bogey Club – Laufzeit für die Desktop-Apps (Mac und Windows). Bildet die Teile von window.claude nach,
// die die App nutzt: db (Daten als Datei auf dem Rechner), assets (Bilder), downloads (Sichern-Dialog)
// und sample (Scorekarte lesen – offline: auf dem Mac mit Apples Texterkennung, unter Windows mit
// Tesseract aus ocr.js, das in der App mitgeliefert wird).
(() => {
  const win = window.bogeyNative?.platform === "windows";
  window.BOGEY_MAC = !win;
  window.BOGEY_WINDOWS = win;
  window.BOGEY_SCAN_HINT = win
    ? "Fotografiere die ausgefüllte Karte möglichst flach und vollständig oder wähle ein PDF, z. B. aus einer Golf-App. Die Texterkennung läuft direkt auf deinem PC – ohne Internet – und liest Par, Lochvorgaben und Schlagzeilen. Gedruckte Karten und PDFs klappen am besten, Handschrift oft nicht: prüfe danach alles in der Karte."
    : "Fotografiere die ausgefüllte Karte möglichst flach und vollständig oder wähle ein PDF, z. B. aus einer Golf-App. Apples Texterkennung liest Par, Lochvorgaben und Schlagzeilen direkt auf deinem Mac – ohne Internet. Gedruckte Karten und PDFs klappen am besten, Handschrift nicht immer: prüfe danach alles in der Karte.";
  window.BOGEY_SCAN_BUSY = win
    ? "Karte wird gelesen … das dauert meist einige Sekunden."
    : "Karte wird gelesen … das dauert meist nur wenige Sekunden, direkt nach dem Start der App etwas länger.";
  if (win) window.BOGEY_OCR_PATHS = {
    script: "vendor/tesseract/tesseract.min.js",
    workerPath: new URL("vendor/tesseract/worker.min.js", location.href).href,
    corePath: new URL("vendor/tesseract/core/", location.href).href,
    langPath: new URL("vendor/tesseract/lang/", location.href).href
  };
  const bridge = win ? window.bogeyNative : window.webkit?.messageHandlers?.bogey;
  const call = (cmd, args = {}) => bridge.postMessage({ cmd, ...args }).then(r => {
    if (r && r.error) { const e = new Error(r.error); e.code = r.error; throw e; }
    return r;
  });

  const toBase64 = blob => new Promise((ok, no) => {
    const fr = new FileReader();
    fr.onload = () => ok(String(fr.result).replace(/^data:[^,]*,/, ""));
    fr.onerror = () => no(fr.error);
    fr.readAsDataURL(blob);
  });

  // ---- Datenbank: alles einmal laden, Änderungen sofort an alle Listener und auf die Platte ----
  let data = null;   // { coll: { id: docData } }
  const loaded = call("db.load").then(d => { data = JSON.parse(d || "{}"); return data; });
  const listeners = new Map();   // coll -> Set(fn)
  const snapshot = coll => ({ docs: Object.entries(data[coll] || {}).map(([id, d]) => ({ id, data: () => JSON.parse(JSON.stringify(d)) })) });
  const notify = coll => (listeners.get(coll) || []).forEach(fn => { try { fn(snapshot(coll)); } catch (e) { console.error(e); } });

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
          return {
            async set(doc) {
              await loaded;
              const clean = JSON.parse(JSON.stringify(doc));
              await call("db.set", { coll, id, data: JSON.stringify(clean) });
              (data[coll] ??= {})[id] = clean; notify(coll);
            },
            async delete() {
              await loaded;
              await call("db.delete", { coll, id });
              if (data[coll]) delete data[coll][id];
              notify(coll);
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

  // ---- Bilder: liegen als Dateien im Datenordner, ausgeliefert unter /_blob/<id> ----
  const assets = {
    async upload(blob) {
      if (blob.size > 8 * 1024 * 1024) { const e = new Error("too_large"); e.code = "too_large"; throw e; }
      if (!/^image\/(jpeg|png|webp|gif)$/.test(blob.type)) { const e = new Error("unsupported_type"); e.code = "unsupported_type"; throw e; }
      return call("assets.upload", { type: blob.type, base64: await toBase64(blob) });
    },
    async delete(id) { await call("assets.delete", { id }); }
  };

  // ---- Downloads: Dialog „Sichern unter …“ des Systems ----
  const downloads = {
    async save({ filename, data }) {
      const blob = data instanceof Blob ? data : new Blob([data]);
      await call("download.save", { filename: filename || "download", base64: await toBase64(blob) });
    }
  };

  // ---- Scorekarte lesen: Bilder an die Texterkennung von macOS, Antwort im selben JSON-Format ----
  let ocrLoad = null;
  const sample = {
    async limits() { return { images: { maxCount: 3 } }; },
    async json(_prompt, opts = {}) {
      if (win) {
        ocrLoad ??= new Promise((res, rej) => { const el = document.createElement("script"); el.src = "ocr.js"; el.onload = res; el.onerror = rej; document.head.appendChild(el); })
          .catch(e => { ocrLoad = null; throw e; });
        await ocrLoad;
        try { return await window.BogeyOCR.read(opts.images || []); }
        catch (e) { console.error(e); const err = new Error("image_rejected"); err.code = "image_rejected"; throw err; }
      }
      const images = [];
      for (const b of opts.images || []) images.push(await toBase64(b));
      return call("scan", { images });
    }
  };

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
