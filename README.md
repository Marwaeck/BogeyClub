# Bogey Club

Privates Golf-Scorebuch: Scorekarten erfassen (Foto, PDF oder TAG-Heuer-Link), mehrere Spieler über viele Runden verfolgen und daraus Jahresstatistik, Ranking, Badges und Platz-Briefings erstellen.

## Inhalt

| Ordner | Was |
|---|---|
| `web/` | Web-App als eine HTML-Datei (läuft als Claude-Artefakt mit Datenbank, Downloads, Bild-Upload). `index.html` + Logo. |
| `ios/GolfScorebuch/` | iOS-App in SwiftUI + SwiftData, Scorekarten-Erkennung offline mit Apple Vision. In Xcode öffnen: `GolfScorebuch.xcodeproj`. |
| `osm/` | Platzkarten aus OpenStreetMap: `fetch.sh` lädt die Rohdaten über Overpass, `osm2map.py` wandelt sie in kompakte Karten-JSON um, `render.js` zeichnet sie als SVG. |
| `server/` | Cloudflare Worker (`worker.js`: API, Bilder, Zugangsprüfung) und `runtime.js`, das im Browser die Claude-Laufzeit (Datenbank, Bilder, Downloads) ersetzt. |
| `public/` | Von `build.mjs` erzeugt: die ausgelieferte Web-App. Nicht von Hand ändern. |
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

## Hosting auf Cloudflare

Die Web-App läuft als ein Cloudflare Worker (`wrangler.jsonc`):

- **App:** `web/index.html` wird von `build.mjs` nach `public/` gebaut (mit `runtime.js`, App-Icon und Manifest für „Zum Home-Bildschirm“).
- **Daten:** D1-Datenbank `bogeyclub` (Tabelle `docs`, eine Zeile je Spieler/Platz/Runde/Platzkarte; wird automatisch angelegt).
- **Bilder:** R2-Bucket `bogeyclub-photos`, ausgeliefert unter `/_blob/<id>`.
- **Zugang:** Cloudflare Access. Der Worker prüft bei jeder Anfrage das Access-Token gegen `ACCESS_TEAM` und `ACCESS_AUD`; sind die leer, bleibt die App geschlossen.
- **Deploy:** Workers Builds, verbunden mit diesem Repo – jeder Push auf `main` wird veröffentlicht.

Im gehosteten Modus gibt es kein Einlesen per Foto (das nutzt in Claude die KI-Funktion), Schläge werden direkt in die Karte getippt.

Lokal testen:

```bash
npm install
printf 'DEV_USER=ich@example.com\nACCESS_TEAM=dev\nACCESS_AUD=dev\n' > .dev.vars   # nur lokal: überspringt Access auf localhost
npx wrangler dev
```

Umzug der Daten aus der Claude-Version: dort **Spieler → Daten-Backup → Backup herunterladen** (enthält auch die Bilder), in der gehosteten App **Backup einspielen**.
