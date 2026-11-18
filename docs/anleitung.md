---
title: Anleitung
permalink: /anleitung/
lead: Installieren, Daten umziehen und Scorekarten einlesen – für Mac, Windows, Android und Web.
---

## Mac {#mac}

**Mit einem Befehl:** Terminal öffnen (Programme → Dienstprogramme), diese Zeile einfügen, Enter drücken:

```
curl -fsSL https://raw.githubusercontent.com/Marwaeck/BogeyClub/main/install/mac.sh | zsh
```

Lädt die neueste Version, legt sie in „Programme“ und startet sie – auch zum Aktualisieren. Oder von Hand:

1. **Bogey-Club-mac-&lt;Version&gt;.zip** aus den [Downloads](https://github.com/{{ site.repository }}/releases) laden, öffnen und **Bogey Club.app** in den Ordner „Programme“ ziehen.
2. Beim ersten Start mit Rechtsklick → **Öffnen** starten (die App ist nicht bei Apple registriert; mit dem Befehl oben entfällt das).
3. Daten liegen unter `~/Library/Application Support/Bogey Club` – Menü **Bogey Club → Datenordner im Finder zeigen**. Einmal am Tag wird automatisch eine Kopie unter „Sicherungen“ abgelegt.

Selbst bauen (Xcode und Node nötig): `npm run mac` im Projektordner → `mac/build/Bogey Club.app`.

## Windows {#windows}

**Mit einem Befehl:** PowerShell öffnen (Start → „PowerShell“ tippen), diese Zeile einfügen, Enter drücken:

```
irm https://raw.githubusercontent.com/Marwaeck/BogeyClub/main/install/windows.ps1 | iex
```

Installiert die neueste Version ohne Administratorrechte, mit Verknüpfung im Startmenü und auf dem Desktop – auch zum Aktualisieren. Oder von Hand:

1. **Bogey-Club-windows-&lt;Version&gt;.zip** aus den [Downloads](https://github.com/{{ site.repository }}/releases) laden und entpacken.
2. **Bogey Club.exe** starten. Fragt Windows nach („Der Computer wurde durch Windows geschützt“): **Weitere Informationen → Trotzdem ausführen**.
3. Daten liegen unter `%APPDATA%\Bogey Club` – Menü **Datei → Datenordner öffnen**.

Selbst bauen (Node nötig): `npm run windows` → `windows/dist/`.

## Android {#android}

1. Auf dem Handy **Bogey-Club-android-&lt;Version&gt;.apk** aus den [Downloads](https://github.com/{{ site.repository }}/releases) laden und öffnen.
2. Beim ersten Mal fragt Android, ob der Browser Apps installieren darf: **Einstellungen → Unbekannte Apps installieren → Zulassen**, dann **Installieren**.
3. Daten liegen auf dem Handy in der App. Zum Umziehen: **Spieler → Daten-Backup**.

Neue Versionen meldet die App von selbst – **Herunterladen** tippen und die APK wieder öffnen; die Daten bleiben.

## Web {#web}

Die [Web-App]({{ "/app/" | relative_url }}) läuft direkt im Browser – ohne Installation, ohne Anmeldung, auf Wunsch über **Zum Home-Bildschirm** wie eine App.

- Deine Daten bleiben **in diesem Browser** auf diesem Gerät; nichts wird hochgeladen. Ein anderes Gerät oder ein anderer Browser hat seinen eigenen Stand.
- Sichern und umziehen über **Spieler → Daten-Backup**. Wer den Browserverlauf samt Website-Daten löscht, löscht auch die Bogey-Club-Daten – vorher ein Backup herunterladen.
- Nach dem ersten Öffnen startet sie auch ohne Internet. Die Texterkennung lädt beim ersten Scannen einmalig etwa 5 MB.

## Updates, Version und Lizenz

- **Updates:** Mac- und Windows-App schauen einmal am Tag auf GitHub nach einer neuen Version und bieten sie mit **Jetzt installieren** an – die App wird ausgetauscht und neu gestartet, die Daten bleiben. Von Hand: Mac **Bogey Club → Nach Updates suchen …**, Windows **Hilfe → Nach Updates suchen …**. Die automatische Suche lässt sich im selben Menü ausschalten.
- **Version:** steht im Fenster **Über Bogey Club**.
- **Lizenz:** privat und kostenlos nutzbar, Quellcode und Gestaltung © Marwaeck, alle Rechte vorbehalten – [LICENSE](https://github.com/{{ site.repository }}/blob/main/LICENSE). Bausteine anderer (Schriften, PDF, Texterkennung, Karten) stehen unter ihren eigenen Lizenzen: [Übersicht](https://github.com/{{ site.repository }}/blob/main/THIRD-PARTY-NOTICES.md), in den Apps unter **Lizenzen der Bausteine …**.

## Daten umziehen

Jede Version kann ein Backup schreiben und einspielen:

1. In der alten Version **Spieler → Daten-Backup → Backup herunterladen** – das ergibt eine Bogey-Datei (`.bogey`), Spieler- und Luftbilder sind mit drin.
2. In der neuen Version die Datei antippen bzw. doppelklicken – oder **Spieler → Daten-Backup → Datei einspielen …** – und bestätigen.

Einträge mit gleicher ID werden überschrieben, neue ergänzt – gelöscht wird nichts.

## Runde an Freunde schicken

Öffne die Runde und tippe auf **Als Datei teilen**. Es entsteht eine kleine Bogey-Datei mit der Runde, den Spielern und dem Platz – per WhatsApp, Mail oder AirDrop verschicken. Wer sie antippt, sieht in Bogey Club eine Vorschau und übernimmt die Runde. Spieler und Plätze, die schon da sind, werden über den Namen zugeordnet und nicht verändert.

## Scorekarte einlesen

**Runden → Neue Runde → Scorekarte einlesen**, dann Foto oder PDF wählen. Erkannt werden Par, Lochvorgaben, Spielerzeilen und – wenn vorhanden – Platzname und Datum. Danach ordnest du die Zeilen den Spielern zu und prüfst die Werte in der Karte.

| Version | Texterkennung | Ohne Internet |
|---|---|---|
| Mac | Apple Vision | ja |
| Windows | Tesseract (in der App enthalten) | ja |
| Web (Browser) | Tesseract im Browser | Bild bleibt im Browser |

> Gedruckte Karten und PDFs klappen am besten. Handschrift wird nicht immer erkannt – dann die fehlenden Schläge direkt in die Karte tippen.
