// ---------- Platzkarten (OpenStreetMap) ----------
const MAP_STYLE = {
  wo: "fill:var(--m-wood)", co: "fill:var(--m-rough)", ro: "fill:var(--m-rough2)", dr: "fill:var(--m-range)",
  fw: "fill:var(--m-fairway)", wa: "fill:var(--m-water);stroke:var(--m-water-s);stroke-width:1", te: "fill:var(--m-tee)",
  gr: "fill:var(--m-green);stroke:var(--m-green-s);stroke-width:1.2", bu: "fill:var(--m-sand);stroke:var(--m-sand-s);stroke-width:.8",
  cl: "fill:var(--m-house)", tr: "fill:none;stroke:var(--m-wood);stroke-width:5;stroke-linecap:round"
};
const mPath = (pts, closed = true) => "M" + pts.map(p => p[0] + " " + p[1]).join("L") + (closed ? "Z" : "");
const holeLen = line => line.slice(1).reduce((s, p, i) => s + Math.hypot(p[0] - line[i][0], p[1] - line[i][1]), 0);
// Bahnen passend zum Platz: Kurzplatz nur, wenn der Platz so heißt; bei 9-Loch-Plätzen nur Bahn 1–9
function mapHoles(map, c) {
  if (!map?.holes) return [];
  const wantShort = /kurz/i.test(c?.name || "");
  let hs = map.holes.filter(h => !!(h.name && /kurz/i.test(h.name)) === wantShort && h.line?.length >= 2);
  if (!hs.length) hs = map.holes.filter(h => h.line?.length >= 2);
  const n = c?.pars?.length || 18;
  const byRef = new Map();
  hs.forEach(h => { const r = parseInt(h.ref, 10); if (r >= 1 && r <= n && !byRef.has(r)) byRef.set(r, h); });
  return [...byRef.entries()].sort((a, b) => a[0] - b[0]).map(([r, h]) => ({ ...h, n: r }));
}
function featuresSVG(map) {
  return map.f.map(([k, pts]) => `<path d="${mPath(pts, k !== "tr")}" style="${MAP_STYLE[k] || "fill:var(--m-rough)"}"/>`).join("");
}
function courseMapSVG(map, c, opts = {}) {
  const pad = 20, W = map.w + 2 * pad, H = map.h + 2 * pad;
  const hs = mapHoles(map, c);
  const lab = Math.max(9, Math.min(16, Math.max(map.w, map.h) / 70));
  let g = `<g transform="translate(${pad} ${pad})">${featuresSVG(map)}`;
  hs.forEach(h => {
    g += `<path d="${mPath(h.line, false)}" style="fill:none;stroke:var(--m-line);stroke-width:${lab / 5};stroke-dasharray:${lab / 2} ${lab / 3};opacity:.85"/>`;
  });
  hs.forEach(h => {
    const [x, y] = h.line[0];
    g += `<g ${opts.clickable ? `class="mhole" data-act="map-hole" data-n="${h.n}" style="cursor:pointer"` : ""}><circle cx="${x}" cy="${y}" r="${lab}" style="fill:var(--m-label);stroke:var(--m-label-s);stroke-width:${lab / 6}"/><text x="${x}" y="${y}" text-anchor="middle" dominant-baseline="central" style="font:700 ${lab * 1.05}px var(--font-display);fill:var(--m-label-t)">${h.n}</text></g>`;
  });
  g += `</g>`;
  return `<svg class="cmap" viewBox="0 0 ${W} ${H}" role="img" aria-label="Platzkarte ${esc(c?.name || "")}"><rect width="${W}" height="${H}" style="fill:var(--m-bg)"/>${g}</svg>`;
}
// Einzelne Bahn: Abschlag unten, Grün oben, mit Länge und Par
function holeMapSVG(map, c, h, opts = {}) {
  const a = h.line[0], b = h.line[h.line.length - 1];
  const ang = Math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / Math.PI;
  const rot = -90 - ang;
  const L = holeLen(h.line), cx = (a[0] + b[0]) / 2, cy = (a[1] + b[1]) / 2;
  const R = rot * Math.PI / 180, cos = Math.cos(R), sin = Math.sin(R);
  const rp = p => [cos * (p[0] - cx) - sin * (p[1] - cy), sin * (p[0] - cx) + cos * (p[1] - cy)];
  const lr = h.line.map(rp);
  const xs = lr.map(p => p[0]), ys = lr.map(p => p[1]);
  const span = Math.max(...ys) - Math.min(...ys), s = (span + 90) / 600;   // Strichstärken relativ zur Größe
  const top = opts.noHead ? 45 : 50 + 34 * s, vh = span + top + 40, vw = Math.max(150, (Math.max(...xs) - Math.min(...xs)) + 130, vh * 0.5);
  const vx = (Math.max(...xs) + Math.min(...xs)) / 2 - vw / 2, vy = Math.min(...ys) - top;
  let g = `<g transform="rotate(${rot}) translate(${-cx} ${-cy})">${featuresSVG(map)}</g>`;
  g += `<path d="${mPath(lr, false)}" style="fill:none;stroke:var(--m-line);stroke-width:${3 * s};stroke-dasharray:${8 * s} ${6 * s}"/>`;
  // 50-m-Markierungen ab Abschlag entlang der Linie
  let acc = 0, next = 50;
  for (let i = 1; i < lr.length; i++) {
    const p = lr[i - 1], q = lr[i], seg = Math.hypot(q[0] - p[0], q[1] - p[1]);
    while (acc + seg >= next && next < L - 20) {
      const t = (next - acc) / seg, x = p[0] + (q[0] - p[0]) * t, y = p[1] + (q[1] - p[1]) * t;
      g += `<circle cx="${x}" cy="${y}" r="${3.2 * s}" style="fill:var(--m-label)"/><text x="${x + 9 * s}" y="${y}" dominant-baseline="central" style="font:600 ${13 * s}px var(--font-display);fill:var(--m-label-t2)">${next}</text>`;
      next += 50;
    }
    acc += seg;
  }
  const t0 = lr[0], tN = lr[lr.length - 1];
  g += `<circle cx="${t0[0]}" cy="${t0[1]}" r="${7 * s}" style="fill:var(--m-label);stroke:var(--m-label-s);stroke-width:${1.5 * s}"/>`;
  g += `<path d="M${tN[0]} ${tN[1]}v${-26 * s}" style="stroke:var(--m-label-t2);stroke-width:${2 * s}"/><path d="M${tN[0]} ${tN[1] - 26 * s}l${16 * s} ${5 * s}l${-16 * s} ${5 * s}z" style="fill:var(--m-flag)"/>`;
  const par = c?.pars?.[h.n - 1] ?? h.par;
  const head = `<rect x="${vx}" y="${vy}" width="${vw}" height="${34 * s}" style="fill:var(--m-head)"/><text x="${vx + 10 * s}" y="${vy + 17 * s}" dominant-baseline="central" style="font:700 ${17 * s}px var(--font-display);fill:var(--m-head-t)">Loch ${h.n}${par ? ` · Par ${par}` : ""} · ${Math.round(L)} m</text>`;
  return `<svg class="hmap" viewBox="${vx} ${vy} ${vw} ${vh}" role="img" aria-label="Bahn ${h.n}"><rect x="${vx}" y="${vy}" width="${vw}" height="${vh}" style="fill:var(--m-bg)"/>${g}${opts.noHead ? "" : head}</svg>`;
}
// Kartenlookup: Dokument in "coursemaps", Schlüssel = c.mapKey oder Teil der Platz-ID vor dem ersten "-"
const MAPS = {};
const mapKeyOf = c => c ? (c.mapKey || String(c.id || "").split("-")[0]) : null;
const mapOf = c => { const m = MAPS[mapKeyOf(c)]; return m?.f?.length ? m : null; };
function holeViewHTML(c) {
  const map = mapOf(c); if (!map) return "";
  const hs = mapHoles(map, c); if (!hs.length) return "";
  const n = state.mapHole?.cid === c.id ? state.mapHole.n : null;
  const h = hs.find(x => x.n === n);
  if (!h) return `<p class="hint">Tippe auf eine Lochnummer, um die Bahn vom Abschlag aus zu sehen.</p>`;
  const i = hs.indexOf(h), prev = hs[(i - 1 + hs.length) % hs.length], next = hs[(i + 1) % hs.length];
  return `<div class="row"><button class="btn ghost" data-act="map-hole" data-cid="${esc(c.id)}" data-n="${prev.n}">← Loch ${prev.n}</button><span class="spacer"></span>
    <button class="btn ghost" data-act="map-hole" data-cid="${esc(c.id)}" data-n="0">Schließen</button><button class="btn ghost" data-act="map-hole" data-cid="${esc(c.id)}" data-n="${next.n}">Loch ${next.n} →</button></div>
    <div class="hmap-wrap">${holeMapSVG(map, c, h)}</div>
    <p class="hint">Länge entlang der eingezeichneten Spiellinie aus OpenStreetMap, nicht vom gelben Abschlag gemessen. Punkte alle 50 m ab Abschlag.</p>`;
}
function courseMapHTML(c, title = "Platzkarte") {
  const map = mapOf(c); if (!map) return "";
  const hs = mapHoles(map, c);
  return `<div class="cmap-block" data-cid="${esc(c.id)}"><h3>${title}</h3>
    <div class="cmap-wrap">${courseMapSVG(map, c, { clickable: hs.length > 0 })}</div>
    ${hs.length ? "" : `<p class="hint">In OpenStreetMap sind für diesen Platz noch keine Bahnen eingezeichnet.</p>`}
    <div class="mhv">${holeViewHTML(c)}</div>
    <p class="hint attr">Kartendaten © OpenStreetMap-Mitwirkende, ODbL</p></div>`;
}
