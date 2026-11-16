// Bogey Club – Service Worker der Web-App (GitHub Pages).
// 1. Liefert Bilder unter …/_blob/<id> aus dem Browser-Speicher (IndexedDB „bogeyclub“, siehe runtime.js).
// 2. Hält die App-Dateien vor, damit die Web-App auch ohne Internet startet (online immer die neueste Fassung).
const CACHE = "bogeyclub-__BUILD__";
const SHELL = __SHELL__;

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith("bogeyclub-") && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

function openDB() {
  return new Promise((ok, no) => {
    const r = indexedDB.open("bogeyclub", 1);
    r.onupgradeneeded = () => {
      const d = r.result;
      if (!d.objectStoreNames.contains("docs")) d.createObjectStore("docs");
      if (!d.objectStoreNames.contains("blobs")) d.createObjectStore("blobs");
    };
    r.onsuccess = () => ok(r.result);
    r.onerror = () => no(r.error);
  });
}

async function blob(id) {
  const d = await openDB();
  const rec = await new Promise((ok, no) => {
    const r = d.transaction("blobs").objectStore("blobs").get(id);
    r.onsuccess = () => ok(r.result); r.onerror = () => no(r.error);
  });
  d.close();
  if (!rec) return new Response("Not found", { status: 404, headers: { "content-type": "text/plain" } });
  return new Response(rec.data, { headers: { "content-type": rec.type, "cache-control": "no-store" } });
}

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return;
  const i = url.pathname.indexOf("/_blob/");
  if (i >= 0) { e.respondWith(blob(decodeURIComponent(url.pathname.slice(i + 7)))); return; }
  if (e.request.method !== "GET") return;
  // Erst das Netz (neueste Fassung), ohne Internet aus dem Vorrat
  e.respondWith(fetch(e.request).then(r => {
    if (r.ok && url.pathname.startsWith(new URL(self.registration.scope).pathname)) {
      const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy));
    }
    return r;
  }).catch(() => caches.match(e.request, { ignoreSearch: true }).then(r => r || Response.error())));
});
