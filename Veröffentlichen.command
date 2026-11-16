#!/bin/zsh
# Doppelklick im Finder: zeigt eine Auswahl – Änderungen zu GitHub hochladen (aktualisieren) oder eine neue
# Version von Mac-, Windows- und Android-App veröffentlichen. Im Terminal dasselbe: „npm run upload“ bzw. „npm run release“.
# Mit Angaben gestartet (z. B. ./Veröffentlichen.command minor "Neu: …") geht es direkt zum Veröffentlichen.
cd "$(dirname "$0")"

finish() { print; read -k 1 "?Fertig – zum Schließen eine Taste drücken."; print; exit 0; }

if (( $# > 0 )); then zsh scripts/release.sh "$@"; finish; fi

VERSION="$(node -p "require('./package.json').version" 2>/dev/null || print -r -- "?")"
print -r -- "Bogey Club – GitHub   (aktuelle Version ${VERSION})"
print
print -r -- "  1  Aktualisieren: Änderungen speichern und zu GitHub hochladen (Web-App und Website)"
print -r -- "  2  Neue Version veröffentlichen, kleiner Schritt (z. B. 1.0.0 → 1.0.1)"
print -r -- "  3  Neue Version veröffentlichen, größerer Schritt (z. B. 1.0.3 → 1.1.0)"
print -r -- "  4  Probelauf: nur anzeigen, was passieren würde"
print -r -- "  5  Android-Schlüssel einrichten (einmalig, damit sich die Android-App aktualisieren lässt)"
print -r -- "  q  Abbrechen"
print
read -k 1 "CHOICE?Auswahl: "; print; print

case "$CHOICE" in
  1) zsh scripts/upload.sh ;;
  2) zsh scripts/release.sh patch ;;
  3) zsh scripts/release.sh minor ;;
  4) print -r -- "— Aktualisieren —"; zsh scripts/upload.sh --probe
     print; print -r -- "— Neue Version —"; zsh scripts/release.sh --probe ;;
  5) zsh scripts/android-key.sh ;;
  *) print -r -- "Abgebrochen." ;;
esac
finish
