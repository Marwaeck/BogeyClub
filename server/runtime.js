// Bogey Club – Laufzeit für das selbst gehostete Bogey Club (Cloudflare Worker).
// Bildet die Teile von window.claude nach, die die App nutzt: db, assets, downloads.
// "sample" (KI-Erkennung) gibt es hier nicht – die App blendet das Foto-Einlesen dann aus.
(() => {
  if (window.claude?.use) return;           // in Claude läuft die echte Laufzeit
  window.BOGEY_HOSTED = true;
  const POLL_MS = 20000;

  async function api(path, opts = {}) {
    const r = await fetch(path, { credentials: "same-origin", ...opts });
    if (r.status === 401 || r.status === 403) { const e = new Error("not_granted"); e.code = "not_granted"; throw e; }
    if (!r.ok) { const e = new Error(`HTTP ${r.status}`); e.code = (await r.json().catch(() => ({}))).code || "error"; throw e; }
    return r.status === 204 ? null : r.json();
  }

  // ---- Datenbank: Collections mit Dokumenten, Änderungen per Polling ----
  const listeners = new Map();   // coll -> Set({ok, err})
  const lastJson = new Map();
  async function refresh(coll) {
    const set = listeners.get(coll); if (!set?.size) return;
    try {
      const docs = await api(`/api/db/${encodeURIComponent(coll)}`);
      const json = JSON.stringify(docs);
      if (json === lastJson.get(coll)) return;
      lastJson.set(coll, json);
      const snap = { docs: docs.map(d => ({ id: d.id, data: () => d.data })) };
      set.forEach(l => { try { l.ok(snap); } catch (e) { console.error(e); } });
    } catch (e) { set.forEach(l => l.err && l.err(e)); }
  }
  const refreshAll = () => [...listeners.keys()].forEach(refresh);
  setInterval(() => { if (document.visibilityState === "visible") refreshAll(); }, POLL_MS);
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") refreshAll(); });

  const db = {
    collection(coll) {
      return {
        onSnapshot(ok, err) {
          if (!listeners.has(coll)) listeners.set(coll, new Set());
          const l = { ok, err }; listeners.get(coll).add(l);
          lastJson.delete(coll); refresh(coll);
          return () => listeners.get(coll).delete(l);
        },
        doc(id) {
          const url = `/api/db/${encodeURIComponent(coll)}/${encodeURIComponent(id)}`;
          return {
            async set(data) { await api(url, { method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify(data) }); lastJson.delete(coll); refresh(coll); },
            async delete() { await api(url, { method: "DELETE" }); lastJson.delete(coll); refresh(coll); },
            async get() { const d = await api(url).catch(() => null); return { id, exists: !!d, data: () => d?.data }; }
          };
        }
      };
    }
  };

  // ---- Bilder (R2) ----
  const assets = {
    async upload(blob) {
      if (blob.size > 8 * 1024 * 1024) { const e = new Error("too_large"); e.code = "too_large"; throw e; }
      if (!/^image\/(jpeg|png|webp|gif)$/.test(blob.type)) { const e = new Error("unsupported_type"); e.code = "unsupported_type"; throw e; }
      return api("/api/assets", { method: "POST", headers: { "content-type": blob.type }, body: blob });
    },
    async delete(id) { await api(`/api/assets/${encodeURIComponent(id)}`, { method: "DELETE" }); }
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

  window.claude = {
    async use(name) {
      if (name === "db") return db;
      if (name === "assets") return assets;
      if (name === "downloads") return downloads;
      return null;
    }
  };
})();
