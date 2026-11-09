// Bogey Club – Cloudflare Worker
// Liefert die App aus (statische Dateien in ./public), speichert Daten in D1 und Bilder in R2.
// Zugang: nur über Cloudflare Access. Jede Anfrage muss ein gültiges Access-Token (JWT) tragen,
// das gegen ACCESS_TEAM (z. B. "bogeyclub" für bogeyclub.cloudflareaccess.com) und ACCESS_AUD geprüft wird.

const COLLS = new Set(["players", "courses", "rounds", "coursemaps"]);
const ID_RE = /^[A-Za-z0-9_\-.~:@+]{1,200}$/;
const MAX_DOC = 900 * 1024;
const MAX_IMG = 8 * 1024 * 1024;

const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
const fail = (status, code, message) => json({ code, message }, status);

// ---------- Cloudflare Access ----------
let certCache = { at: 0, keys: null };
async function accessKeys(team) {
  if (certCache.keys && Date.now() - certCache.at < 3600_000) return certCache.keys;
  const r = await fetch(`https://${team}.cloudflareaccess.com/cdn-cgi/access/certs`);
  if (!r.ok) throw new Error("certs");
  const { keys } = await r.json();
  certCache = { at: Date.now(), keys };
  return keys;
}
const b64url = s => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), c => c.charCodeAt(0));

async function verifyAccess(request, env) {
  if (env.DEV_USER && new URL(request.url).hostname === "localhost") return { email: env.DEV_USER };   // nur lokal (wrangler dev, .dev.vars)
  const team = (env.ACCESS_TEAM || "").trim(), aud = (env.ACCESS_AUD || "").trim();
  if (!team || !aud) return { error: "setup" };
  const token = request.headers.get("cf-access-jwt-assertion") || (request.headers.get("cookie") || "").match(/CF_Authorization=([^;]+)/)?.[1];
  if (!token) return { error: "no_token" };
  const [h, p, s] = token.split(".");
  if (!h || !p || !s) return { error: "bad_token" };
  let header, payload;
  try { header = JSON.parse(new TextDecoder().decode(b64url(h))); payload = JSON.parse(new TextDecoder().decode(b64url(p))); }
  catch { return { error: "bad_token" }; }
  if (header.alg !== "RS256") return { error: "bad_token" };
  const now = Math.floor(Date.now() / 1000);
  const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!auds.includes(aud) || payload.exp < now || payload.iss !== `https://${team}.cloudflareaccess.com`) return { error: "bad_token" };
  const jwk = (await accessKeys(team)).find(k => k.kid === header.kid);
  if (!jwk) { certCache.keys = null; return { error: "bad_token" }; }
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64url(s), new TextEncoder().encode(`${h}.${p}`));
  return ok ? { email: payload.email || payload.sub || "unbekannt" } : { error: "bad_token" };
}

const SETUP_PAGE = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bogey Club – Einrichtung</title><body style="font:16px/1.5 system-ui;max-width:560px;margin:40px auto;padding:0 16px;color:#142019">
<h1 style="color:#1c6641">Bogey Club ist noch nicht freigeschaltet</h1>
<p>Der Zugangsschutz (Cloudflare Access) ist noch nicht vollständig eingerichtet. Solange das so ist, bleibt die App aus Sicherheitsgründen geschlossen.</p>
<p>Es fehlen die Einstellungen <code>ACCESS_TEAM</code> und <code>ACCESS_AUD</code> in <code>wrangler.jsonc</code>.</p></body>`;

// ---------- D1 ----------
let schemaReady = false;
async function ensureSchema(db) {
  if (schemaReady) return;
  await db.batch([
    db.prepare("CREATE TABLE IF NOT EXISTS docs (coll TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, updated_at INTEGER NOT NULL, updated_by TEXT, PRIMARY KEY (coll, id))"),
    db.prepare("CREATE TABLE IF NOT EXISTS assets (id TEXT PRIMARY KEY, type TEXT NOT NULL, size INTEGER NOT NULL, created_at INTEGER NOT NULL, created_by TEXT)")
  ]);
  schemaReady = true;
}

async function handleApi(request, env, url, user) {
  const parts = url.pathname.split("/").slice(2).map(decodeURIComponent);   // ["db", coll, id?] | ["assets", id?] | ["me"]
  const method = request.method;
  await ensureSchema(env.DB);

  if (parts[0] === "me" && method === "GET") return json({ email: user.email });

  if (parts[0] === "db") {
    const [, coll, id] = parts;
    if (!COLLS.has(coll)) return fail(404, "not_found", "Unbekannte Sammlung");
    if (!id) {
      if (method !== "GET") return fail(405, "method", "Nicht erlaubt");
      const { results } = await env.DB.prepare("SELECT id, data FROM docs WHERE coll = ? ORDER BY id").bind(coll).all();
      return json(results.map(r => ({ id: r.id, data: JSON.parse(r.data) })));
    }
    if (!ID_RE.test(id)) return fail(400, "bad_id", "Ungültige ID");
    if (method === "GET") {
      const r = await env.DB.prepare("SELECT data FROM docs WHERE coll = ? AND id = ?").bind(coll, id).first();
      return r ? json({ id, data: JSON.parse(r.data) }) : fail(404, "not_found", "Nicht gefunden");
    }
    if (method === "PUT") {
      const body = await request.text();
      if (body.length > MAX_DOC) return fail(413, "too_large", "Dokument zu groß");
      let data; try { data = JSON.parse(body); } catch { return fail(400, "bad_json", "Kein gültiges JSON"); }
      if (!data || typeof data !== "object" || Array.isArray(data)) return fail(400, "bad_json", "Objekt erwartet");
      await env.DB.prepare("INSERT INTO docs (coll, id, data, updated_at, updated_by) VALUES (?, ?, ?, ?, ?) ON CONFLICT(coll, id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at, updated_by = excluded.updated_by")
        .bind(coll, id, JSON.stringify(data), Date.now(), user.email).run();
      return new Response(null, { status: 204 });
    }
    if (method === "DELETE") {
      await env.DB.prepare("DELETE FROM docs WHERE coll = ? AND id = ?").bind(coll, id).run();
      return new Response(null, { status: 204 });
    }
    return fail(405, "method", "Nicht erlaubt");
  }

  if (parts[0] === "assets") {
    const id = parts[1];
    if (!id && method === "POST") {
      const type = (request.headers.get("content-type") || "").split(";")[0];
      if (!/^image\/(jpeg|png|webp|gif)$/.test(type)) return fail(415, "unsupported_type", "Nur JPG, PNG, WebP oder GIF");
      const buf = await request.arrayBuffer();
      if (buf.byteLength > MAX_IMG) return fail(413, "too_large", "Bild zu groß");
      const newId = crypto.randomUUID().replace(/-/g, "");
      await env.PHOTOS.put(newId, buf, { httpMetadata: { contentType: type } });
      await env.DB.prepare("INSERT INTO assets (id, type, size, created_at, created_by) VALUES (?, ?, ?, ?, ?)").bind(newId, type, buf.byteLength, Date.now(), user.email).run();
      return json({ id: newId, url: `/_blob/${newId}` }, 201);
    }
    if (id && method === "DELETE") {
      if (!/^[0-9a-f]{32}$/.test(id)) return fail(400, "bad_id", "Ungültige ID");
      await env.PHOTOS.delete(id);
      await env.DB.prepare("DELETE FROM assets WHERE id = ?").bind(id).run();
      return new Response(null, { status: 204 });
    }
    return fail(405, "method", "Nicht erlaubt");
  }
  return fail(404, "not_found", "Unbekannter Pfad");
}

async function handleBlob(request, env, id) {
  if (!/^[0-9a-f]{32}$/.test(id)) return new Response("Not found", { status: 404 });
  const obj = await env.PHOTOS.get(id);
  if (!obj) return new Response("Not found", { status: 404 });
  const headers = new Headers({ "cache-control": "private, max-age=31536000, immutable", etag: obj.httpEtag });
  obj.writeHttpMetadata(headers);
  if (request.method === "HEAD") return new Response(null, { headers });
  return new Response(obj.body, { headers });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const auth = await verifyAccess(request, env).catch(() => ({ error: "bad_token" }));
    if (auth.error === "setup") return url.pathname.startsWith("/api/") ? fail(503, "setup", "Zugang noch nicht eingerichtet") : new Response(SETUP_PAGE, { status: 503, headers: { "content-type": "text/html; charset=utf-8" } });
    if (auth.error) return url.pathname.startsWith("/api/") ? fail(401, "not_granted", "Bitte anmelden") : new Response("Bitte über die Bogey-Club-Adresse anmelden.", { status: 401 });

    if (url.pathname.startsWith("/api/")) {
      try { return await handleApi(request, env, url, auth); }
      catch (e) { console.error(e); return fail(500, "error", "Serverfehler"); }
    }
    if (url.pathname.startsWith("/_blob/")) return handleBlob(request, env, url.pathname.slice(7));
    return env.ASSETS.fetch(request);
  }
};
