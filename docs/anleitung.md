---
title: Anleitung
permalink: /anleitung/
lead: Installieren, Daten umziehen und Scorekarten einlesen – für Mac, Windows, iPhone und Web.
---

## Mac {#mac}

1. **Bogey Club.app** aus den [Downloads](https://github.com/{{ site.repository }}/releases) laden und in den Ordner „Programme“ ziehen.
2. Beim ersten Start mit Rechtsklick → **Öffnen** starten (die App ist nicht bei Apple registriert).
3. Daten liegen unter `~/Library/Application Support/Bogey Club` – Menü **Bogey Club → Datenordner im Finder zeigen**. Einmal am Tag wird automatisch eine Kopie unter „Sicherungen“ abgelegt.

Selbst bauen (Xcode und Node nötig): `npm run mac` im Projektordner → `mac/build/Bogey Club.app`.

## Windows {#windows}

1. **Bogey-Club-portable.zip** aus den [Downloads](https://github.com/{{ site.repository }}/releases) laden und entpacken.
2. **Bogey Club.exe** starten. Fragt Windows nach („Der Computer wurde durch Windows geschützt“): **Weitere Informationen → Trotzdem ausführen**.
3. Daten liegen unter `%APPDATA%\Bogey Club` – Menü **Datei → Datenordner öffnen**.

Selbst bauen (Node nötig): `npm run windows` → `windows/dist/`.

## iPhone {#iphone}

Das Projekt `ios/GolfScorebuch/GolfScorebuch.xcodeproj` in Xcode öffnen, das eigene iPhone wählen und auf **Ausführen** tippen. Die Scorekarte scannt der eingebaute Dokumentenscanner, gelesen wird mit Apples Texterkennung direkt auf dem Gerät.

## Web {#web}

Die Web-App läuft als Cloudflare Worker mit Datenbank und Bildspeicher; Zugang über Cloudflare Access. Einrichtung und lokales Testen stehen in der [README](https://github.com/{{ site.repository }}#hosting-auf-cloudflare).

## Daten umziehen

Jede Version kann ein Backup schreiben und einspielen:

1. In der alten Version **Spieler → Daten-Backup → Backup herunterladen** (Spieler- und Luftbilder sind mit drin).
2. In der neuen Version **Spieler → Daten-Backup → Backup einspielen …** und bestätigen.

Einträge mit gleicher ID werden überschrieben, neue ergänzt – gelöscht wird nichts.

## Scorekarte einlesen

**Runden → Neue Runde → Scorekarte einlesen**, dann Foto oder PDF wählen. Erkannt werden Par, Lochvorgaben, Spielerzeilen und – wenn vorhanden – Platzname und Datum. Danach ordnest du die Zeilen den Spielern zu und prüfst die Werte in der Karte.

| Version | Texterkennung | Ohne Internet |
|---|---|---|
| iPhone, Mac | Apple Vision | ja |
| Windows | Tesseract (in der App enthalten) | ja |
| Web (Browser) | Tesseract im Browser | Bild bleibt im Browser |

> Gedruckte Karten und PDFs klappen am besten. Handschrift wird nicht immer erkannt – dann die fehlenden Schläge direkt in die Karte tippen.
