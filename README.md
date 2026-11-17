# Bogey Club

![Bogey Club](design/social-card.png)

Privates Golf-Scorebuch: Scorekarten erfassen (Foto, PDF oder TAG-Heuer-Link), mehrere Spieler über viele Runden verfolgen und daraus Jahresstatistik, Ranking, Badges und Platz-Briefings erstellen.

## Inhalt

| Ordner | Was |
|---|---|
| `web/` | Web-App als eine HTML-Datei (läuft als Claude-Artefakt mit Datenbank, Downloads, Bild-Upload). `index.html` + Logo. |
| `mac/` | Mac-App: dieselbe Oberfläche wie `web/`, aber ohne Claude – Daten auf dem Mac, Scorekarten-Erkennung offline mit Apple Vision. |
| `BogeyScan/` | Gemeinsame Scorekarten-Erkennung für iPhone- und Mac-App (Swift-Paket): Apple Vision liest den Text auf dem Gerät, danach werden Lochnummern als Spaltenraster genutzt, leere Zellen nachgelesen und Par, Lochvorgaben und Spielerzeilen erkannt. Tests: `cd BogeyScan && swift test`. |
| `windows/` | Windows-App (Electron): dieselbe Oberfläche, Daten auf dem PC, Scorekarten-Erkennung offline mit mitgelieferter Texterkennung (Tesseract). |
| `android/` | Android-App (WebView, Kotlin): dieselbe Oberfläche, Daten auf dem Handy, Scorekarten-Erkennung offline mit mitgelieferter Texterkennung (Tesseract). Die APK baut GitHub Actions. |
| `ios/GolfScorebuch/` | iOS-App in SwiftUI + SwiftData, Scorekarten-Erkennung offline mit Apple Vision (über `BogeyScan`). In Xcode öffnen: `GolfScorebuch.xcodeproj`. |
| `osm/` | Platzkarten aus OpenStreetMap: `fetch.sh` lädt die Rohdaten über Overpass, `osm2map.py` wandelt sie in kompakte Karten-JSON um, `render.js` zeichnet sie als SVG. |
| `server/` | Bausteine der Web-App im Browser: `runtime.js` ersetzt die Claude-Laufzeit (Datenbank und Bilder im Browser, Downloads, Scorekarte lesen), `sw.js` (Service Worker: Bilder, Offline), `ocr.js` – die Scorekarten-Erkennung im Browser (auch in Windows- und Android-App), `icons/`. |
| `docs/app/` | Von `build.mjs` erzeugt: die Web-App auf GitHub Pages. Nicht von Hand ändern. |
| `docs/` | Website für GitHub Pages mit eigenem Jekyll-Theme (Farben, Schriften und Logo der App): Startseite, Funktionen, Downloads, Anleitung. Einschalten unter Settings → Pages → Branch `main`, Ordner `/docs`. |
| `design/` | Frühere Icon-Entwürfe und das GitHub-Vorschaubild `social-card.png` (gezeichnet von `make-social-card.swift`; hochladen unter Settings → General → Social preview). |

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

Runden, Spieler und Plätze liegen nicht im Repo. Sicherung in jeder App über **Spieler → Daten-Backup** (iPhone: **Mehr → Daten-Backup**).

## Dateiformat .bogey

Backups und geteilte Runden sind Bogey-Dateien (`.bogey`, MIME-Typ `application/vnd.bogeyclub`, Typ-ID `club.bogey.file`). Alle Apps melden die Endung beim System an: Doppelklick bzw. Antippen (Dateien, Mail, WhatsApp, „Teilen an Bogey Club“ auf Android) öffnet Bogey Club mit einer Vorschau vor dem Einspielen.

Aufbau – ein ZIP-Container:

| Eintrag | Inhalt |
|---|---|
| `mimetype` | `application/vnd.bogeyclub`, unkomprimiert, als erster Eintrag |
| `bogey.json` | `{ format: "bogey", version: 1, kind: "backup" \| "round", app, exportedAt, players, courses, rounds, coursemaps }` – dieselben Dokumente wie in der Datenbank der Web-App, Platzkarten als Objekt je Kartenschlüssel |
| `images/<id>.jpg` | Spieler- und Luftbilder (ID wie im Feld `photo`) |

- **`kind: "backup"`** – alles. Beim Einspielen werden Einträge mit gleicher ID überschrieben und neue ergänzt, gelöscht wird nichts.
- **`kind: "round"`** – eine Runde mit ihren Spielern, dem Platz und ggf. der Platzkarte („Als Datei teilen“ in der Runde; iPhone: Runde nach rechts wischen). Beim Empfänger werden Spieler und Plätze über ID oder Namen zugeordnet und nie verändert; nur Fehlendes wird angelegt.
- Schreiben/Lesen: `web/index.html` (Abschnitt „Daten-Backup und Bogey-Dateien“, für Web, Claude, Mac, Windows, Android) und `BogeyScan/Sources/BogeyScan/BogeyFile.swift` (iPhone-App, mit Tests). Ältere JSON-Backups werden weiter gelesen.
- Geöffnete Dateien reichen die Apps über `window.bogeyOpenFile(name, base64)` an die Oberfläche weiter (Mac: `WebController.openFile`, Windows: `main.js`, Android: `MainActivity.handleOpenIntent`, installierte Web-App: File Handling API in `server/runtime.js`).

## Mac-App (ohne Claude)

Die Mac-App zeigt `web/index.html` in einem eigenen Fenster und ersetzt die Claude-Laufzeit durch den Mac selbst (`mac/runtime.js` ↔ Swift):

- **Daten:** `~/Library/Application Support/Bogey Club/daten.json` (Spieler, Plätze, Runden, Platzkarten), Bilder im Unterordner `Bilder`, einmal täglich eine Kopie unter `Sicherungen` (die letzten 30). Menü **Bogey Club → Datenordner im Finder zeigen**.
- **Scorekarte einlesen:** Foto oder PDF wird mit der Texterkennung von macOS gelesen (offline). Lochnummern-Zeile dient als Spaltenraster, leere Zellen werden einzeln nachgelesen. Gedruckte Karten klappen gut, Handschrift weniger – Werte danach in der Karte prüfen.
- **Speichern:** PDFs, Rundenkarten und Backups über den normalen „Sichern unter“-Dialog.
- **Offline:** Schriften, jsPDF und pdf.js liegen in `mac/vendor/` (neu laden mit `node mac/fetch-vendor.mjs`). Nur die Links zu Apple Karten / Google Maps brauchen Internet.

Bauen (Xcode muss installiert sein):

```bash
npm run mac          # oder ./mac/build.sh  → mac/build/Bogey Club.app
cd mac && swift test # Tests für Datenablage und Scorekarten-Erkennung
```

Das Programm-Icon (Scorekarte mit Bogey-Kästchen, Bleistift, Golfball; Club-Farben, Schrift Barlow Condensed) zeichnet `mac/icon/make-icon.swift` für alle Plattformen: Mac (`mac/AppIcon.icns`), iPhone (`AppIcon.appiconset/icon.png`) , Web-App (`server/icons/`) und das Logo im App-Kopf und in den PDFs (`web/bogey-club-logo.png`). Neu erzeugen: `swift mac/icon/make-icon.swift && iconutil -c icns mac/build/AppIcon.iconset -o mac/AppIcon.icns`, danach `npm run build` und `npm run mac`.

Die App danach in den Ordner „Programme“ ziehen. Sie ist nur lokal signiert; beim ersten Öffnen auf einem anderen Mac per Rechtsklick → „Öffnen“ starten.

Umzug der Daten: in der Claude-Version oder der Web-App **Spieler → Daten-Backup → Backup herunterladen**, in der Mac-App **Backup einspielen**.

## Web-App im Browser (GitHub Pages)

Die Web-App läuft ohne Server als Teil der Website: **https://marwaeck.github.io/BogeyClub/app/**

- **App:** `npm run build` (`build.mjs`) baut `web/index.html` nach `docs/app/` – mit `server/runtime.js`, App-Icon, Manifest für „Zum Home-Bildschirm“, Schriften und PDF-Bibliotheken (aus `mac/vendor`). `docs/app/` wird mit hochgeladen; GitHub Pages veröffentlicht den Ordner `docs/` bei jedem Push auf `main`. `npm run upload` und `npm run release` bauen vorher automatisch neu.
- **Daten und Bilder:** im jeweiligen Browser (IndexedDB) – jedes Gerät und jeder Browser hat seinen eigenen Stand, wie bei den Apps. Umzug und Sicherung über **Spieler → Daten-Backup**. Offene Tabs gleichen sich gegenseitig ab.
- **Bilder und Offline:** Der Service Worker (`server/sw.js`) liefert Bilder unter `_blob/<id>` aus dem Browser-Speicher und hält die App-Dateien vor, damit sie auch ohne Internet startet.
- **Kein Zugangsschutz nötig:** Die Seite enthält keine Daten – was eingetragen wird, verlässt den Browser nicht.

## Installieren mit einem Befehl

Lädt jeweils die neueste Version aus den GitHub-Releases (Daten bleiben unberührt, auch zum Aktualisieren):

```bash
# Mac (Terminal) → /Applications/Bogey Club.app
curl -fsSL https://raw.githubusercontent.com/Marwaeck/BogeyClub/main/install/mac.sh | zsh
```

```powershell
# Windows (PowerShell) → %LOCALAPPDATA%\Programs\Bogey Club, mit Startmenü- und Desktop-Verknüpfung
irm https://raw.githubusercontent.com/Marwaeck/BogeyClub/main/install/windows.ps1 | iex
```

Skripte: `install/mac.sh`, `install/windows.ps1`. Voraussetzung: ein veröffentlichtes Release (`npm run release`).

## Version, Lizenz und Updates (Mac und Windows)

- **Version:** eine Nummer für beide Apps, `version` in `package.json` im Projektordner. `mac/build.sh` und `windows/dist.js` übernehmen sie (Über-Fenster, Dateinamen).
- **Lizenz:** `LICENSE` – private Nutzung kostenlos, Quellcode und Gestaltung © Marwaeck, alle Rechte vorbehalten. Bausteine anderer: `THIRD-PARTY-NOTICES.md`, Lizenztexte in `licenses/`. Beides liegt in den Apps bei (Menü „Lizenz …“ / „Lizenzen der Bausteine …“).
- **Updater:** beide Apps fragen einmal am Tag (und über „Nach Updates suchen …“) das neueste GitHub-Release ab. Gibt es eine höhere Version mit `Bogey-Club-mac-<Version>.zip` bzw. `Bogey-Club-windows-<Version>.zip`, bieten sie **Jetzt installieren** an: Mac prüft Bundle-ID, Version und Signatur, tauscht die App aus und startet neu; Windows entpackt die ZIP und kopiert sie nach dem Beenden über den App-Ordner. Daten bleiben unberührt. Logik und Tests: `mac/Sources/BogeyCore/UpdateCheck.swift`, `UpdateInstaller.swift`, `windows/updater.js`.
- **Doppelklick auf Veröffentlichen.command** im Finder zeigt eine Auswahl: *Aktualisieren* (nur hochladen), *Neue Version* (kleiner oder größerer Schritt) oder *Probelauf*. Beide Wege holen zuerst neuere Änderungen von GitHub, und die Arbeitsdateien von Craft Anything (`craft.json`, `investigation.cany/` usw.) werden nie mit hochgeladen.
- **Aktualisieren – ohne neue Version:** `npm run upload` (optional `-- "Was geändert wurde"`, `-- --probe` für einen Probelauf). Baut die Web-Version, speichert alles (commit) und lädt es hoch (push). Website und Web-App (GitHub Pages) aktualisieren sich dann von selbst; Mac- und Windows-App bekommen ein Update erst mit einer neuen Version.
- **Speichern, hochladen und veröffentlichen – ein Befehl:** `npm run release` im Projektordner. Erhöht die Version (1.0.0 → 1.0.1; `npm run release -- minor` bzw. `-- 2.0.0` für größere Sprünge), fragt nach den Neuerungen, speichert alles (commit) und lädt es mit dem Tag `v<Version>` hoch (push). Den Rest erledigt GitHub Actions: Mac-, Windows- und Android-App bauen und das GitHub-Release `v<Version>` mit beiden ZIP-Dateien und der APK anlegen (etwa 10 Minuten, mitverfolgen mit `gh run watch`). Das erste Mal wird 1.0.0 veröffentlicht. `npm run release -- --probe` zeigt nur, was passieren würde. Braucht die GitHub-CLI (`gh auth login`), aber kein Xcode.
- **Automatische Builds:** `.github/workflows/build.yml` baut bei jedem Push auf `main` und bei jedem Pull Request die Web-Version, führt die Tests aus (BogeyScan, Mac-Datenablage, Windows) und baut Mac-, Windows- und Android-App. Die ZIP-Dateien und die APK liegen 14 Tage unter **Actions → Lauf → Artifacts**. Bei einem Tag `v<Version>` wird zusätzlich das Release veröffentlicht.

## Windows-App (ohne Claude)

Gleicher Aufbau wie die Mac-App: `web/index.html` in einem eigenen Fenster, `mac/runtime.js` als Brücke (unter Windows über `windows/preload.js`), Datenablage in `windows/store.js` im selben Format wie auf dem Mac.

- **Daten:** `%APPDATA%\Bogey Club\daten.json`, Bilder unter `Bilder`, tägliche Kopien unter `Sicherungen`. Menü **Datei → Datenordner öffnen**.
- **Scorekarte einlesen:** `server/ocr.js` mit Tesseract, komplett in der App enthalten (kein Internet nötig).
- **Umzug:** wie beim Mac über **Spieler → Daten-Backup**.

Bauen (auf Mac oder Windows, Node nötig):

```bash
npm run windows      # → windows/dist/Bogey-Club-windows-<Version>.zip (darin „Bogey Club.exe“)
cd windows && npm test
```

Die ZIP-Datei auf dem PC entpacken und „Bogey Club.exe“ starten (Windows fragt beim ersten Start evtl. nach, weil die App nicht signiert ist: „Weitere Informationen → Trotzdem ausführen“). Ein Installationsprogramm mit Startmenü-Eintrag lässt sich nur unter Windows (oder auf Intel-Macs) bauen: `cd windows && npm run dist:installer`. Der Updater ist für die ZIP-Version gebaut.

## Android-App (ohne Claude)

Gleicher Aufbau wie die Windows-App: `web/index.html` in einer WebView, `mac/runtime.js` als Brücke (unter Android über `window.BogeyAndroid` in `android/app/src/main/java/club/bogey/android/MainActivity.kt`), Datenablage in `Store.kt` im selben Format wie auf Mac und Windows.

- **APK von GitHub:** Jeder Push auf `main` baut die APK (**Actions → Lauf → Artifacts → android**), jede neue Version (`npm run release`) hängt `Bogey-Club-android-<Version>.apk` an das Release.
- **Installieren:** APK auf dem Handy aus den [Releases](https://github.com/Marwaeck/BogeyClub/releases) laden und öffnen; beim ersten Mal fragt Android, ob der Browser Apps installieren darf („Unbekannte Apps installieren“ erlauben). Android 8 oder neuer.
- **Signierschlüssel (einmalig):** `npm run android-key` (oder Punkt 5 in **Veröffentlichen.command**) legt einen eigenen Schlüssel an, speichert ihn außerhalb des Projekts unter `~/Library/Application Support/Bogey Club Entwicklung/` und hinterlegt ihn als geheimen Wert bei GitHub. Nur dann lassen sich neue Versionen über die installierte App spielen – ohne Schlüssel signiert GitHub jedes Mal mit einem anderen Testschlüssel. Den Ordner bitte sichern.
- **Daten:** im internen Speicher der App (`daten.json`, `Bilder`, `Sicherungen` – wie Mac und Windows). Umzug über **Spieler → Daten-Backup**.
- **Scorekarte einlesen:** Kamera oder Datei; `server/ocr.js` mit Tesseract, komplett in der App enthalten.
- **Updates:** Die App schaut einmal am Tag auf GitHub nach einer neuen Version und bietet **Herunterladen** an; die APK dann öffnen und installieren, die Daten bleiben.

Selbst bauen (Node, JDK 17 und Android-SDK nötig): `npm run android` → `android/app/build/outputs/apk/release/`.

## Texterkennung auf allen Plattformen

| Wo | Womit | Offline |
|---|---|---|
| iPhone-App | Apple Vision über `BogeyScan` | ja |
| Mac-App | Apple Vision über `BogeyScan` | ja |
| Windows-App | Tesseract.js in `server/ocr.js`, mitgeliefert | ja |
| Android-App | Tesseract.js in `server/ocr.js`, mitgeliefert | ja |
| Web-App in Claude | Claude (KI) | nein |
| Web-App im Browser (GitHub Pages) | Tesseract.js in `server/ocr.js` – Apples Vision gibt es im Browser nicht | Bild bleibt im Browser; das Erkennungsmodul (~5 MB) lädt beim ersten Mal von jsDelivr |

`server/ocr.js` ist eine Übertragung von `BogeyScan/Sources/BogeyScan/ScorecardParser.swift` nach JavaScript – Änderungen an der Auswertung bitte in beiden Dateien machen. Handschrift liest Tesseract deutlich schlechter als Apple Vision.

Umzug der Daten aus der Claude-Version: dort **Spieler → Daten-Backup → Backup herunterladen** (enthält auch die Bilder), in der Web-App **Backup einspielen**.
