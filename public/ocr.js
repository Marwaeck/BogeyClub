// Bogey Club – Scorekarten-Erkennung im Browser (gehostete Version).
// Apples Texterkennung (Vision) gibt es nur in der iPhone- und Mac-App; im Browser liest hier
// Tesseract.js (Open Source, läuft auf dem Gerät, Bilder verlassen den Browser nicht).
// Die Auswertung (Zeilen, Spaltenraster, Par/Lochvorgaben/Spieler) entspricht BogeyScan/ScorecardParser.swift.
(() => {
  const TESSERACT = "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js";

  // ---------- Auswertung: Wörter mit Positionen (0…1, Ursprung unten links) → Scorekarte ----------
  const SKIP_EXACT = new Set(["loch", "hole", "holes", "bahn", "löcher", "rot", "gelb", "blau", "weiß", "weiss", "schwarz", "orange", "tee", "gir", "cr", "date"]);
  const SKIP_PREFIX = ["meter", "yard", "länge", "laenge", "punkte", "stableford", "netto", "brutto", "putt", "fairway", "green", "datum", "total", "summe", "gesamt", "marker", "zähler", "unterschrift", "signature", "slope", "abschlag", "vorgabeschl", "score", "ergebnis"];
  const SI_WORDS = ["hcp", "hdcp", "si", "index", "hc", "vorgabe", "handicap", "stroke", "lochvorgabe"];
  const HOLE_WORDS = ["loch", "hole", "holes", "bahn", "löcher"];
  const OCR_MAP = { O: "0", o: "0", D: "0", l: "1", I: "1", i: "1", "|": "1", Z: "2", z: "2", S: "5", s: "5", G: "6", b: "6", T: "7", B: "8", g: "9", q: "9" };
  const isLetter = c => /\p{L}/u.test(c);
  const words = s => s.toLowerCase().split(/[^\p{L}]+/u).filter(Boolean);

  function parseNumber(raw) {
    const t = String(raw).replace(/^[.,:;\-–_()[\]*]+|[.,:;\-–_()[\]*]+$/g, "");
    if (/^-?\d+$/.test(t)) return parseInt(t, 10);
    if (t.length < 1 || t.length > 2) return null;
    if (t.length === 2 && [...t].every(isLetter)) return null;
    if (t.length === 1 && !"OolISZsTBgq|".includes(t)) return null;
    const m = [...t].map(c => OCR_MAP[c] ?? c).join("");
    return /^\d+$/.test(m) ? parseInt(m, 10) : null;
  }

  function buildLines(tokens) {
    if (!tokens.length) return [];
    const hs = tokens.map(t => t.h).sort((a, b) => a - b);
    const tol = hs[Math.floor(hs.length / 2)] * 0.6;
    const groups = [];
    for (const t of [...tokens].sort((a, b) => (b.y + b.h / 2) - (a.y + a.h / 2))) {
      const my = t.y + t.h / 2, last = groups[groups.length - 1];
      if (last) {
        const ref = last.reduce((s, x) => s + x.y + x.h / 2, 0) / last.length;
        if (Math.abs(ref - my) < tol) { last.push(t); continue; }
      }
      groups.push([t]);
    }
    return groups.map(g => {
      const cells = [...g].sort((a, b) => a.x - b.x).map(t => ({ text: t.text, value: parseNumber(t.text), x: t.x + t.w / 2 }));
      const gh = g.map(t => t.h).sort((a, b) => a - b);
      return {
        cells, y: g.reduce((s, t) => s + t.y + t.h / 2, 0) / g.length, height: gh[Math.floor(gh.length / 2)],
        get label() { return this.cells.filter(c => c.value == null).map(c => c.text).join(" "); },
        get numbers() { return this.cells.filter(c => c.value != null); }
      };
    });
  }

  function holeRun(line) {
    const nums = line.numbers.filter(c => c.value <= 18);
    let best = [], run = [];
    for (const c of nums) {
      const last = run[run.length - 1];
      run = last && c.value === last.value + 1 ? [...run, c] : [c];
      if (run.length > best.length) best = run;
    }
    if (!best.length || !(best.length === 9 || best.length === 18) || !(best[0].value === 1 || best[0].value === 10)) return null;
    return { first: best[0].value, xs: best.map(c => c.x) };
  }

  const isHoleLabel = line => words(line.label).some(w => HOLE_WORDS.includes(w));

  function cleanName(s) {
    return s.split(" ").filter(w => !/\d/.test(w) && [...w].some(isLetter)).join(" ").replace(/^[ .,:;\-–_()[\]]+|[ .,:;\-–_()[\]]+$/g, "");
  }

  function classify(line) {
    const label = line.label.trim(), ws = words(label);
    const vals = line.numbers.map(c => c.value);
    const small = vals.filter(v => v >= 1 && v <= 20), big = vals.filter(v => v > 20);
    if (big.length > small.length) return { kind: "skip" };
    if (ws.includes("par")) return { kind: "par" };
    if (ws.some(w => SI_WORDS.includes(w))) return { kind: "si" };
    if (ws.some(w => SKIP_EXACT.has(w) || SKIP_PREFIX.some(p => w.startsWith(p)))) return { kind: "skip" };
    if (!label) {
      if (small.length >= 9 && small.every(v => v >= 3 && v <= 5)) return { kind: "par" };
      if (small.length >= 9 && new Set(small).size === small.length && small.includes(1)) return { kind: "si" };
      return small.length >= 5 ? { kind: "player", name: "" } : { kind: "skip" };
    }
    if (!ws.some(w => w.length >= 2) || small.length < 5) return { kind: "skip" };
    return { kind: "player", name: cleanName(label) };
  }

  function align(line, columns, kind) {
    const max = kind === "si" ? 18 : kind === "par" ? 6 : 15;
    const nums = line.numbers.filter(c => c.value >= 1 && c.value <= max);
    if (!columns || columns.length < 2) return nums.map(c => c.value);
    const diffs = columns.slice(1).map((x, i) => x - columns[i]).sort((a, b) => a - b);
    const spacing = diffs[Math.floor((columns.length - 1) / 2)];
    const out = new Array(columns.length).fill(0), used = new Set();
    columns.forEach((x, j) => {
      let best = null;
      nums.forEach((c, k) => {
        if (used.has(k)) return;
        const d = Math.abs(c.x - x);
        if (d < spacing * 0.5 && (!best || d < best.d)) best = { k, d };
      });
      if (best) { used.add(best.k); out[j] = nums[best.k].value; }
    });
    return out;
  }

  function clusterColumns(lines) {
    const rows = lines.filter(l => classify(l).kind !== "skip" || isHoleLabel(l))
      .map(l => l.numbers.filter(c => c.value >= 1 && c.value <= 20).map(c => c.x).sort((a, b) => a - b))
      .filter(xs => xs.length >= 3);
    if (rows.length < 2) return null;
    const diffs = rows.flatMap(xs => xs.slice(1).map((x, i) => x - xs[i])).filter(d => d > 0.005).sort((a, b) => a - b);
    if (!diffs.length) return null;
    const spacing = diffs[Math.floor(diffs.length / 5)];
    const clusters = [];
    for (const x of rows.flat().sort((a, b) => a - b)) {
      const last = clusters[clusters.length - 1];
      if (last && x - last[last.length - 1] < spacing * 0.45) last.push(x); else clusters.push([x]);
    }
    const need = Math.max(2, Math.round(rows.length * 0.3));
    const cols = clusters.filter(c => c.length >= need).map(c => c.reduce((s, x) => s + x, 0) / c.length);
    return cols.length >= 5 ? { cols, spacing } : null;
  }

  function sections(lines) {
    const result = [];
    let cur = { offset: 0, columns: null, spacing: 0, lines: [], holeCount: 0 };
    const finish = () => {
      if (!cur.columns) { const c = clusterColumns(cur.lines); if (c) { cur.columns = c.cols; cur.spacing = c.spacing; } }
      if (cur.columns || cur.lines.length) result.push(cur);
    };
    for (const line of lines) {
      const run = holeRun(line);
      if (run) {
        finish();
        const d = run.xs.slice(1).map((x, i) => x - run.xs[i]).sort((a, b) => a - b);
        cur = { offset: run.first - 1, columns: run.xs, spacing: d[Math.floor((run.xs.length - 1) / 2)], lines: [], holeCount: run.first - 1 + run.xs.length };
      } else if (isHoleLabel(line)) {
        finish();
        const lowest = Math.min(...line.numbers.map(c => c.value).filter(v => v >= 1 && v <= 18), 1e9);
        cur = { offset: lowest >= 10 && lowest < 1e9 ? 9 : 0, columns: null, spacing: 0, lines: [line], holeCount: 0 };
      } else cur.lines.push(line);
    }
    finish();
    return result;
  }

  function missingCells(tokens) {
    const out = [];
    for (const sec of sections(buildLines(tokens))) {
      if (!sec.columns) continue;
      for (const line of sec.lines) {
        if (classify(line).kind === "skip" && !isHoleLabel(line)) continue;
        for (const x of sec.columns) {
          if (!line.numbers.some(c => Math.abs(c.x - x) < sec.spacing * 0.5)) out.push({ x, y: line.y, spacing: sec.spacing, height: line.height });
        }
      }
    }
    return out;
  }

  function findDate(texts) {
    const s = texts.join(" ");
    const iso = s.match(/\b(20\d\d)-(\d\d)-(\d\d)\b/); if (iso) return iso[0];
    for (const m of s.matchAll(/\b(\d{1,2})[./](\d{1,2})[./](\d{2}|\d{4})\b/g)) {
      const d = +m[1], mo = +m[2]; let y = +m[3]; if (y < 100) y += 2000;
      if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12 && y >= 2000 && y <= 2100) return `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
    }
    return null;
  }

  function findCourse(lines) {
    for (const l of lines) {
      if (l.numbers.length) continue;
      const t = l.label.split(" ").filter(w => !/\d/.test(w)).join(" "), lo = t.toLowerCase();
      if (t.length >= 6 && t.length <= 60 && (lo.includes("golf") || lo.includes("country") || lo.startsWith("gc ") || lo.includes(" gc") || lo.includes("club"))) return t;
    }
    return null;
  }

  function parse(pages) {
    const par = {}, si = {}, players = [];
    let holeCount = 0, maxPlayer = 0, course = null, date = null;
    for (const tokens of pages) {
      const lines = buildLines(tokens);
      date ??= findDate(tokens.map(t => t.text));
      course ??= findCourse(lines);
      for (const sec of sections(lines)) {
        holeCount = Math.max(holeCount, sec.holeCount);
        for (const line of sec.lines) {
          const k = classify(line);
          if (k.kind === "skip") continue;
          const values = align(line, sec.columns, k.kind);
          if (values.filter(v => v > 0).length < 3) continue;
          const o = sec.offset;
          if (k.kind === "par") values.forEach((v, i) => { if (v > 0) par[o + i] = v; });
          else if (k.kind === "si") values.forEach((v, i) => { if (v > 0) si[o + i] = v; });
          else {
            maxPlayer = Math.max(maxPlayer, o + values.length);
            const key = (k.name.toLowerCase().split(" ")[0] || "");
            let p = key && players.find(x => x.key === key);
            if (!p) { p = { key, name: k.name, strokes: {} }; players.push(p); }
            values.forEach((v, i) => { if (p.strokes[o + i] == null || v > 0) p.strokes[o + i] = v; });
          }
        }
      }
    }
    const parCount = Math.max(-1, ...Object.keys(par).map(Number)) + 1;
    const n = Math.max(holeCount, parCount, maxPlayer) >= 14 ? 18 : 9;
    const list = m => Array.from({ length: n }, (_, i) => m[i] ?? 0);
    let parList = list(par); if (parList.filter(v => v >= 3 && v <= 6).length < n - 2) parList = [];
    let siList = list(si); if (new Set(siList.filter(v => v > 0)).size < n - 2) siList = [];
    return {
      course, date, par: parList, strokeIndex: siList,
      players: players.map((p, i) => ({ name: p.name || `Spieler ${i + 1}`, strokes: list(p.strokes) })).filter(p => p.strokes.some(v => v > 0))
    };
  }

  // ---------- Tesseract: Bild → Wörter, leere Zellen gezielt nachlesen ----------
  let workerPromise = null;
  function loadScript(src) {
    return new Promise((res, rej) => { const s = document.createElement("script"); s.src = src; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
  }
  function getWorker() {
    // Die Windows-App liefert alles mit (window.BOGEY_OCR_PATHS) und braucht dann kein Internet
    const P = window.BOGEY_OCR_PATHS || {};
    const opts = P.workerPath ? { workerPath: P.workerPath, corePath: P.corePath, langPath: P.langPath, workerBlobURL: false } : {};
    workerPromise ??= (window.Tesseract ? Promise.resolve() : loadScript(P.script || TESSERACT))
      .then(() => window.Tesseract.createWorker("deu", 1, opts))
      .catch(e => { workerPromise = null; throw e; });
    return workerPromise;
  }

  async function tokensOf(worker, image, W, H, rect, psm) {
    await worker.setParameters({ tessedit_pageseg_mode: psm });
    const { data } = await worker.recognize(image, rect ? { rectangle: rect } : {});
    const out = [];
    for (const w of data.words || []) {
      for (const part of String(w.text).split(/[ |]+/).filter(Boolean)) {
        const b = w.bbox;
        out.push({ text: part, x: b.x0 / W, y: 1 - b.y1 / H, w: (b.x1 - b.x0) / W, h: (b.y1 - b.y0) / H });
      }
    }
    return out;
  }

  async function readImage(blob) {
    const bmp = await createImageBitmap(blob);
    const W = bmp.width, H = bmp.height;
    const cv = document.createElement("canvas"); cv.width = W; cv.height = H;
    cv.getContext("2d").drawImage(bmp, 0, 0);
    const worker = await getWorker();
    const tokens = await tokensOf(worker, cv, W, H, null, "6");    // 6 = ein gleichmäßiger Textblock – liest Tabellenzeilen am besten
    for (const cell of missingCells(tokens).slice(0, 120)) {
      for (const [fw, fh] of [[1.2, 2.4], [2.2, 4.0]]) {
        const w = cell.spacing * fw, h = cell.height * fh;
        const left = Math.max(0, Math.round((cell.x - w / 2) * W)), top = Math.max(0, Math.round((1 - cell.y - h / 2) * H));
        const rect = { left, top, width: Math.min(W - left, Math.round(w * W)), height: Math.min(H - top, Math.round(h * H)) };
        if (rect.width < 4 || rect.height < 4) continue;
        const found = (await tokensOf(worker, cv, W, H, rect, "6"))
          .filter(t => parseNumber(t.text) != null && Math.abs(t.x + t.w / 2 - cell.x) < cell.spacing * 0.45)
          .sort((a, b) => Math.abs(a.x + a.w / 2 - cell.x) - Math.abs(b.x + b.w / 2 - cell.x));
        if (found.length) { tokens.push(found[0]); break; }
      }
    }
    return tokens;
  }

  window.BogeyOCR = {
    parse, parseNumber, missingCells,
    async read(blobs) {
      const pages = [];
      for (const b of blobs) pages.push(await readImage(b));
      return parse(pages);
    }
  };
})();
