// Erzeugt den Web-Teil der Mac-App (mac/build/web) bzw. mit „--target windows“ der Windows-App
// (windows/build/web) und mit „--target android“ der Android-App (android/build/web) aus web/index.html – derselben Datei wie das
// Claude-Artefakt und die Web-App auf GitHub Pages. Statt Claude kommt mac/runtime.js zum Einsatz,
// Bibliotheken und Schriften werden aus mac/vendor geladen, damit alles offline funktioniert.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync, cpSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { gunzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";

const MAC = dirname(fileURLToPath(import.meta.url));
const ROOT = join(MAC, "..");
const TARGET = process.argv.includes("--target") ? process.argv[process.argv.indexOf("--target") + 1] : "mac";
if (!["mac", "windows", "android"].includes(TARGET)) throw new Error(`Unbekanntes Ziel: ${TARGET}`);
const WINDOWS = TARGET === "windows", ANDROID = TARGET === "android";
const OUT = TARGET === "mac" ? join(MAC, "build", "web") : join(ROOT, TARGET, "build", "web");

let app = readFileSync(join(ROOT, "web", "index.html"), "utf8");

// Pflicht-Ersetzungen: fehlt eine Stelle, hat sich die Web-App geändert und das hier muss angepasst werden
function must(from, to) {
  if (!app.includes(from)) throw new Error(`Stelle in web/index.html nicht gefunden: ${from.slice(0, 80)}`);
  app = app.split(from).join(to);
}
// Nur Texte – fehlt die Stelle, bleibt der Originaltext stehen
const soft = (from, to) => { app = app.split(from).join(to); };

// Schriften lokal statt von Google Fonts
app = app.replace(/<link rel="preconnect"[^>]*>\n?/g, "");
app = app.replace(/<link rel="stylesheet" href="https:\/\/fonts\.googleapis\.com[^>]*>/, '<link rel="stylesheet" href="vendor/fonts/fonts.css">');
if (app.includes("fonts.googleapis.com")) throw new Error("Google-Fonts-Verweis nicht ersetzt");

// PDF-Bibliotheken lokal statt vom CDN
app = app.replace(/const JSPDF = "[^"]*";/, 'const JSPDF = "vendor/jspdf.umd.min.js";');
app = app.replace(/const AUTOTABLE = "[^"]*";/, 'const AUTOTABLE = "vendor/jspdf.plugin.autotable.min.js";');
app = app.replace(/const PDFJS = "[^"]*";/, 'const PDFJS = "vendor/pdfjs/";');
if (/cdnjs\./.test(app)) throw new Error("CDN-Verweis nicht ersetzt");

// Texte, die auf Claude verweisen
must('window.BOGEY_BROWSER ? "Gespeichert in diesem Browser" : "Gespeichert in deinem Claude-Konto"', ANDROID ? '"Gespeichert auf diesem Handy"' : WINDOWS ? '"Gespeichert auf diesem PC"' : '"Gespeichert auf diesem Mac"');
soft("Du hast der Seite den Zugriff auf Claude nicht erlaubt. Trage die Werte direkt ein.", "Die Texterkennung ist nicht verfügbar. Trage die Werte direkt ein.");
soft("Speichern ist in dieser Ansicht nicht möglich. Öffne die Seite in der Claude-App oder auf claude.ai.", "Speichern ist gerade nicht möglich.");

// Mac-Laufzeit vor dem App-Skript laden
const i = app.indexOf("<script>");
if (i < 0) throw new Error("App-Skript nicht gefunden");
app = app.slice(0, i) + '<script src="runtime.js"></script>\n' + app.slice(i);

const head = `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
`;
app = head + app.replace(/<meta name="claude:[^>]*>\n?/g, "") + "\n</html>\n";

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
writeFileSync(join(OUT, "index.html"), app);
copyFileSync(join(MAC, "runtime.js"), join(OUT, "runtime.js"));
copyFileSync(join(ROOT, "web", "bogey-club-logo.png"), join(OUT, "bogey-club-logo.png"));
cpSync(join(MAC, "vendor"), join(OUT, "vendor"), { recursive: true });
if (WINDOWS || ANDROID) {
  // Texterkennung im Browser (wie die gehostete Version), aber komplett mitgeliefert
  const NM = join(ROOT, TARGET, "node_modules");
  if (!existsSync(join(NM, "tesseract.js"))) throw new Error(`Texterkennung fehlt – zuerst: npm --prefix ${TARGET} install`);
  const T = join(OUT, "vendor", "tesseract");
  mkdirSync(join(T, "core"), { recursive: true }); mkdirSync(join(T, "lang"), { recursive: true });
  copyFileSync(join(ROOT, "server", "ocr.js"), join(OUT, "ocr.js"));
  for (const f of ["tesseract.min.js", "worker.min.js"]) copyFileSync(join(NM, "tesseract.js", "dist", f), join(T, f));
  for (const f of ["tesseract-core-simd-lstm.wasm.js", "tesseract-core-lstm.wasm.js"]) copyFileSync(join(NM, "tesseract.js-core", f), join(T, "core", f));
  const LANG = join(NM, "@tesseract.js-data", "deu", "4.0.0_best_int", "deu.traineddata.gz");
  // Android entpackt .gz-Dateien in der APK ohnehin (und benennt sie um) – darum dort gleich entpackt beilegen
  if (ANDROID) writeFileSync(join(T, "lang", "deu.traineddata"), gunzipSync(readFileSync(LANG)));
  else copyFileSync(LANG, join(T, "lang", "deu.traineddata.gz"));
  if (ANDROID) {   // Lizenzen liegen in der APK bei (Windows: neben der .exe, siehe windows/dist.js)
    cpSync(join(ROOT, "licenses"), join(OUT, "Lizenzen"), { recursive: true });
    copyFileSync(join(ROOT, "LICENSE"), join(OUT, "Lizenzen", "LICENSE.txt"));
    copyFileSync(join(ROOT, "THIRD-PARTY-NOTICES.md"), join(OUT, "Lizenzen", "Drittanbieter.txt"));
  }
  if (WINDOWS) copyFileSync(join(ROOT, "web", "bogey-club-logo.png"), join(ROOT, "windows", "build", "icon.png"));   // Programm-Icon
}
console.log(`${TARGET}/build/web erstellt`);
