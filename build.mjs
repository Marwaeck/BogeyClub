// Erzeugt ./public für den Cloudflare Worker aus web/index.html (dieselbe Datei wie das Claude-Artefakt).
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync } from "node:fs";

rmSync("public", { recursive: true, force: true });
mkdirSync("public/icons", { recursive: true });

let app = readFileSync("web/index.html", "utf8");
const i = app.indexOf("<script>");
if (i < 0) throw new Error("App-Skript nicht gefunden");
app = app.slice(0, i) + '<script src="/runtime.js"></script>\n' + app.slice(i);

const head = `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#1c6641">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Bogey Club">
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" type="image/png" href="/icons/icon-192.png">
<link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
`;
writeFileSync("public/index.html", head + app.replace(/<meta name="claude:[^>]*>\n?/g, "") + "\n</html>\n");

copyFileSync("web/bogey-club-logo.png", "public/bogey-club-logo.png");
copyFileSync("server/runtime.js", "public/runtime.js");
for (const f of ["icon-192.png", "icon-512.png", "apple-touch-icon.png"]) copyFileSync(`server/icons/${f}`, `public/icons/${f}`);
writeFileSync("public/manifest.webmanifest", JSON.stringify({
  name: "Bogey Club", short_name: "Bogey Club", lang: "de", start_url: "/", display: "standalone",
  background_color: "#eef3ef", theme_color: "#1c6641",
  icons: [{ src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" }, { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png" }]
}, null, 2));
console.log("public/ erstellt");
