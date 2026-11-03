# Bogey Club

Privates Golf-Scorebuch: Scorekarten erfassen (Foto, PDF oder TAG-Heuer-Link), mehrere Spieler über viele Runden verfolgen und daraus Jahresstatistik, Ranking, Badges und Platz-Briefings erstellen.

## Inhalt

| Ordner | Was |
|---|---|
| `web/` | Web-App als eine HTML-Datei (läuft als Claude-Artefakt mit Datenbank, Downloads, Bild-Upload). `index.html` + Logo. |
| `ios/GolfScorebuch/` | iOS-App in SwiftUI + SwiftData, Scorekarten-Erkennung offline mit Apple Vision. In Xcode öffnen: `GolfScorebuch.xcodeproj`. |
| `osm/` | Platzkarten aus OpenStreetMap: `fetch.sh` lädt die Rohdaten über Overpass, `osm2map.py` wandelt sie in kompakte Karten-JSON um, `render.js` zeichnet sie als SVG. |
| `design/` | App-Icon / Wappen und frühere Entwürfe. |

## Golf-Logik (WHS / DGV)

- Spielvorgabe = round(HI · Slope / 113 + CR − Par); 9-Loch-Plätze mit halbem Index
- Stableford = max(0, 2 + Par + Vorgabeschläge − Schläge)
- Score-Differential mit Netto-Doppelbogey als Lochmaximum, virtuelles Handicap nach WHS-Tabelle (beste n der letzten 20), 9-Loch-Runden mit erwartetem Ergebnis für die zweite Hälfte (0,52 · HI + 1,2)
- Striche zählen im Brutto als Netto-Doppelbogey (Par + 2 + Vorgabeschläge)

## Platzkarten neu erzeugen

```bash
cd osm
./fetch.sh bruchsal Bruchsal                         # → bruchsal.json
python3 osm2map.py bruchsal.json bruchsal.map.json Bruchsal
```

Die Karte wird in der Web-App in der Datenbank-Collection `coursemaps` gespeichert (Dokument-ID = Teil der Platz-ID vor dem ersten „-“, oder die volle Platz-ID für Sonderfälle), Feld `json` mit dem Inhalt der `.map.json`. Kartendaten © OpenStreetMap-Mitwirkende, ODbL.

## Daten

Runden, Spieler und Plätze liegen nicht im Repo. Sicherung über die Web-App: Reiter **Spieler → Daten-Backup**.
