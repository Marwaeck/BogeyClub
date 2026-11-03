#!/bin/bash
# Lädt die OSM-Golfdaten eines Platzes über die Overpass-API.
# Aufruf: ./fetch.sh <id> <namens-regex>    → schreibt <id>.json
id="$1"; rx="$2"
q="[out:json][timeout:90];(way[\"leisure\"=\"golf_course\"][\"name\"~\"$rx\",i];relation[\"leisure\"=\"golf_course\"][\"name\"~\"$rx\",i];)->.gc;.gc out geom;.gc map_to_area->.a;(way(area.a)[\"golf\"];relation(area.a)[\"golf\"];node(area.a)[\"golf\"];way(area.a)[\"natural\"=\"water\"];way(area.a)[\"natural\"=\"wood\"];way(area.a)[\"landuse\"=\"forest\"];way(area.a)[\"natural\"=\"tree_row\"];);out geom;"
for w in 5 10 20 40; do
  curl -sS -m 120 -A "BogeyClub/1.0 (private scorebook)" "https://overpass-api.de/api/interpreter" --data-urlencode "data=$q" -o "$id.json.tmp"
  if head -c 1 "$id.json.tmp" | grep -q '{'; then mv "$id.json.tmp" "$id.json"; echo "$id ok $(wc -c < $id.json)"; exit 0; fi
  echo "$id retry in $w"; sleep $w
done
echo "$id FAILED"; head -c 200 "$id.json.tmp"
