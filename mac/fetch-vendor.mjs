// Lädt einmalig die Bibliotheken und Schriften, die die Web-App sonst aus dem Netz holt,
// nach mac/vendor/ – damit die Mac-App komplett offline läuft. Nur nötig, wenn die Versionen
// in web/index.html geändert werden. Aufruf: node mac/fetch-vendor.mjs
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "vendor");
const CDN = "https://cdnjs.cloudflare.com/ajax/libs/";
const FILES = {
  "jspdf.umd.min.js": CDN + "jspdf/2.5.1/jspdf.umd.min.js",
  "jspdf.plugin.autotable.min.js": CDN + "jspdf-autotable/3.8.2/jspdf.plugin.autotable.min.js",
  "pdfjs/pdf.min.js": CDN + "pdf.js/3.11.174/pdf.min.js",
  "pdfjs/pdf.worker.min.js": CDN + "pdf.js/3.11.174/pdf.worker.min.js",
};
const FONTS = "https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=Public+Sans:wght@400;500;600&display=swap";
const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

async function get(url) {
  const r = await fetch(url, { headers: { "user-agent": UA } });
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  return Buffer.from(await r.arrayBuffer());
}

rmSync(OUT, { recursive: true, force: true });
mkdirSync(join(OUT, "pdfjs"), { recursive: true });
mkdirSync(join(OUT, "fonts"), { recursive: true });
for (const [name, url] of Object.entries(FILES)) writeFileSync(join(OUT, name), await get(url));

// Schriften: nur lateinische Zeichensätze, Dateien lokal ablegen und im CSS umschreiben
const css = (await get(FONTS)).toString("utf8");
const blocks = css.split(/(?=\/\* )/).filter(b => /^\/\* latin(-ext)? \*\//.test(b));
let out = "/* Barlow Condensed und Public Sans, SIL Open Font License 1.1 (Google Fonts) */\n";
let i = 0;
for (let b of blocks) {
  const m = b.match(/url\((https:[^)]+)\)/);
  if (!m) continue;
  const fam = b.match(/font-family: '([^']+)'/)[1].replace(/\s+/g, "");
  const w = b.match(/font-weight: (\d+)/)[1];
  const sub = b.startsWith("/* latin-ext") ? "latin-ext" : "latin";
  const name = `${fam}-${w}-${sub}.woff2`;
  writeFileSync(join(OUT, "fonts", name), await get(m[1]));
  out += b.replace(m[1], name);
  i++;
}
writeFileSync(join(OUT, "fonts", "fonts.css"), out);
console.log(`mac/vendor erstellt (${Object.keys(FILES).length} Skripte, ${i} Schriftdateien)`);
