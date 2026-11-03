"""OSM-Golfdaten (Overpass JSON) -> kompakte Platzkarte für Bogey Club.
Ausgabe: {"v":1,"w":breite_m,"h":hoehe_m,"f":[[kind,[[x,y],...]],...],"holes":[{"ref","par","line":[[x,y],...],"name"}],"attr":"© OpenStreetMap-Mitwirkende"}
Koordinaten in Metern, Ursprung oben links (y nach unten), auf 0.5 m gerundet und vereinfacht.
Aufruf: python3 osm2map.py in.json out.json [namensfilter]
"""
import json, math, sys
from shapely.geometry import Polygon, LineString, MultiPolygon, box
from shapely.ops import unary_union, linemerge, polygonize

src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
els = d["elements"]

def geom_ll(e):
    return [(p["lon"], p["lat"]) for p in e.get("geometry", []) if p]

# Platzgrenze(n)
import re
crx = re.compile(sys.argv[3], re.I) if len(sys.argv) > 3 and sys.argv[3] else None
courses = [e for e in els if e.get("tags", {}).get("leisure") == "golf_course" and (not crx or crx.search(e["tags"].get("name", "")))]
rings = []
for e in courses:
    if e["type"] == "way":
        g = geom_ll(e)
        if len(g) >= 4: rings.append(Polygon(g))
    else:
        lines = [LineString([(p["lon"], p["lat"]) for p in m["geometry"]]) for m in e.get("members", []) if m.get("role") in ("outer", "") and m.get("geometry")]
        polys = list(polygonize(linemerge(lines))) if lines else []
        rings += polys
boundary = unary_union([r.buffer(0) for r in rings]) if rings else None

from shapely.geometry import Point
if boundary is not None and not boundary.is_empty:
    zone = boundary.buffer(0.0015)
    def inside(e):
        g = e.get("geometry") or ([{"lon": e["lon"], "lat": e["lat"]}] if "lon" in e else [])
        g = [p for p in g if p]
        return any(zone.contains(Point(p["lon"], p["lat"])) for p in g[::max(1, len(g)//6)] + g[-1:])
    els = [e for e in els if e.get("tags", {}).get("leisure") == "golf_course" and e in courses or inside(e)]
lat0 = None
pts = [(p["lon"], p["lat"]) for e in els for p in e.get("geometry", []) if p]
pts += [(e["lon"], e["lat"]) for e in els if e["type"] == "node"]
if boundary is not None and not boundary.is_empty:
    minx, miny, maxx, maxy = boundary.bounds
else:
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    minx, miny, maxx, maxy = min(xs), min(ys), max(xs), max(ys)
lat0 = (miny + maxy) / 2
kx = 111320 * math.cos(math.radians(lat0)); ky = 110540
def proj(lon, lat): return ((lon - minx) * kx, (maxy - lat) * ky)
W = (maxx - minx) * kx; H = (maxy - miny) * ky
clip = box(-60, -60, W + 60, H + 60)

def rnd(c): return [round(c[0] * 2) / 2, round(c[1] * 2) / 2]
def coords(geom, tol):
    g = geom.simplify(tol, preserve_topology=True)
    return [rnd(c) for c in g.exterior.coords] if isinstance(g, Polygon) else [rnd(c) for c in g.coords]

KIND = {"fairway": "fw", "green": "gr", "tee": "te", "bunker": "bu", "rough": "ro", "driving_range": "dr", "water_hazard": "wa", "lateral_water_hazard": "wa", "clubhouse": "cl"}
feats = []
if boundary is not None and not boundary.is_empty:
    geoms = boundary.geoms if isinstance(boundary, MultiPolygon) else [boundary]
    for g in geoms:
        feats.append(["co", coords(Polygon([proj(*c) for c in g.exterior.coords]), 1.5)])
holes = []
for e in els:
    t = e.get("tags", {})
    g = geom_ll(e)
    if e["type"] != "way" or len(g) < 2: continue
    kind = None
    if t.get("golf") in KIND: kind = KIND[t["golf"]]
    elif t.get("natural") == "water" or t.get("water"): kind = "wa"
    elif t.get("natural") == "wood" or t.get("landuse") == "forest": kind = "wo"
    elif t.get("natural") == "tree_row": kind = "tr"
    if t.get("golf") == "hole":
        line = LineString([proj(*c) for c in g])
        ref = t.get("ref") or (re.search(r"\d+", t.get("name", "")) or [None])[0]
        holes.append({"ref": ref, "tee": next((c for c in ("gelb", "rot", "blau", "weiß", "weiss", "schwarz") if c in (t.get("name") or "").lower()), None), "par": int(t["par"]) if str(t.get("par", "")).isdigit() else None,
                      "hcp": int(t["handicap"]) if str(t.get("handicap", "")).isdigit() else None,
                      "name": t.get("name"), "line": [rnd(c) for c in line.simplify(0.5).coords]})
        continue
    if not kind: continue
    xy = [proj(*c) for c in g]
    if kind == "tr":
        geom = LineString(xy).intersection(clip)
        if geom.is_empty or not isinstance(geom, LineString): continue
        feats.append([kind, coords(geom, 1)]); continue
    if len(xy) < 4 or xy[0] != xy[-1]: continue
    poly = Polygon(xy).buffer(0)
    if kind in ("wo", "wa"): poly = poly.intersection(clip)
    if poly.is_empty: continue
    for p in (poly.geoms if hasattr(poly, "geoms") else [poly]):
        if isinstance(p, Polygon) and p.area > 2:
            feats.append([kind, coords(p, 0.6 if kind in ("gr", "bu", "te") else 1.2)])
# Doppelte Bahnen (je Abschlagfarbe): gelb bevorzugen, sonst ohne Farbe, sonst die erste
pref = sys.argv[4] if len(sys.argv) > 4 else "gelb"
best = {}
for h in holes:
    k = (h["ref"], bool(h["name"] and "kurz" in h["name"].lower()))
    score = 2 if h["tee"] == pref else 1 if h["tee"] is None else 0
    if k not in best or score > best[k][0]: best[k] = (score, h)
holes = [h for _, h in best.values()]
for h in holes: h.pop("tee", None)
order = {"wo": 0, "co": 1, "ro": 2, "dr": 3, "fw": 4, "wa": 5, "tr": 6, "te": 7, "gr": 8, "bu": 9, "cl": 10}
feats.sort(key=lambda f: order.get(f[0], 5))
# Pins
pins = [rnd(proj(e["lon"], e["lat"])) for e in els if e["type"] == "node" and e.get("tags", {}).get("golf") == "pin"]
out = {"v": 1, "w": round(W), "h": round(H), "f": feats, "holes": holes, "pins": pins,
       "name": (courses[0].get("tags", {}).get("name") if courses else None), "attr": "© OpenStreetMap-Mitwirkende"}
json.dump(out, open(dst, "w"), separators=(",", ":"))
from collections import Counter
print(dst, "bytes", len(json.dumps(out, separators=(",", ":"))), "W", round(W), "H", round(H), Counter(f[0] for f in feats), "holes", len(holes))
