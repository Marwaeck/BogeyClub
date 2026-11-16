// Erzeugt die Web-App für GitHub Pages: docs/app/ aus web/index.html (dieselbe Datei wie das Claude-Artefakt).
// Läuft ohne Server: Daten und Bilder bleiben im Browser (server/runtime.js), Bilder und Offline-Betrieb über
// den Service Worker (server/sw.js). Schriften und PDF-Bibliotheken liegen bei (aus mac/vendor), alle Pfade
// sind relativ – die App läuft so unter https://marwaeck.github.io/BogeyClub/app/.
// docs/app/ wird mit hochgeladen (GitHub Pages veröffentlicht den Ordner docs/ so, wie er ist).
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync, cpSync, readdirSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, relative } from "node:path";

const OUT = "docs/app";
rmSync(OUT, { recursive: true, force: true });
mkdirSync(join(OUT, "icons"), { recursive: true });

let app = readFileSync("web/index.html", "utf8");
const must = (re, to, what) => { if (!re.test(app)) throw new Error(`Stelle in web/index.html nicht gefunden: ${what}`); app = app.replace(re, to); };

// Schriften und PDF-Bibliotheken mitliefern (dieselben Dateien wie in den Apps)
app = app.replace(/<link rel="preconnect"[^>]*>\n?/g, "");
must(/<link rel="stylesheet" href="https:\/\/fonts\.googleapis\.com[^>]*>/, '<link rel="stylesheet" href="lib/fonts/fonts.css">', "Google Fonts");
must(/const JSPDF = "[^"]*";/, 'const JSPDF = "lib/jspdf.umd.min.js";', "JSPDF");
must(/const AUTOTABLE = "[^"]*";/, 'const AUTOTABLE = "lib/jspdf.plugin.autotable.min.js";', "AUTOTABLE");
must(/const PDFJS = "[^"]*";/, 'const PDFJS = "lib/pdfjs/";', "PDFJS");
if (/fonts\.googleapis\.com|cdnjs\./.test(app)) throw new Error("Externer Verweis nicht ersetzt");

// Bilder relativ zur App (der Service Worker liefert sie aus)
app = app.split("/_blob/").join("_blob/");

const i = app.indexOf("<script>");
if (i < 0) throw new Error("App-Skript nicht gefunden");
app = app.slice(0, i) + '<script src="runtime.js"></script>\n' + app.slice(i);

const head = `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#1c6641">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Bogey Club">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" type="image/png" href="icons/icon-192.png">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
`;
writeFileSync(join(OUT, "index.html"), head + app.replace(/<meta name="claude:[^>]*>\n?/g, "") + "\n</html>\n");

copyFileSync("web/bogey-club-logo.png", join(OUT, "bogey-club-logo.png"));
copyFileSync("server/runtime.js", join(OUT, "runtime.js"));
copyFileSync("server/ocr.js", join(OUT, "ocr.js"));
cpSync("mac/vendor", join(OUT, "lib"), { recursive: true });
for (const f of ["icon-192.png", "icon-512.png", "apple-touch-icon.png"]) copyFileSync(`server/icons/${f}`, join(OUT, "icons", f));
writeFileSync(join(OUT, "manifest.webmanifest"), JSON.stringify({
  name: "Bogey Club", short_name: "Bogey Club", lang: "de", start_url: "./", scope: "./", display: "standalone",
  background_color: "#eef3ef", theme_color: "#1c6641",
  icons: [{ src: "icons/icon-192.png", sizes: "192x192", type: "image/png" }, { src: "icons/icon-512.png", sizes: "512x512", type: "image/png" }]
}, null, 2) + "\n");

// Service Worker: Liste der App-Dateien und Prüfsumme (neue Fassung → neuer Vorrat)
const files = [];
const walk = dir => readdirSync(dir).sort().forEach(f => { const p = join(dir, f); statSync(p).isDirectory() ? walk(p) : files.push(p); });
walk(OUT);
const hash = createHash("sha256");
for (const f of files) hash.update(f).update(readFileSync(f));
const shell = ["./", ...files.map(f => relative(OUT, f)).filter(f => f !== "index.html")];
writeFileSync(join(OUT, "sw.js"), readFileSync("server/sw.js", "utf8")
  .replace("__BUILD__", hash.digest("hex").slice(0, 12))
  .replace("__SHELL__", JSON.stringify(shell)));
console.log(`${OUT}/ erstellt (${files.length + 1} Dateien)`);
