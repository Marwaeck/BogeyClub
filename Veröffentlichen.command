#!/bin/zsh
# Doppelklick im Finder: speichert alles, lädt es zu GitHub hoch und veröffentlicht eine neue Version
# von Mac- und Windows-App (dasselbe wie „npm run release“ im Terminal).
cd "$(dirname "$0")"
zsh scripts/release.sh "$@"
print
read -k 1 "?Fertig – zum Schließen eine Taste drücken."
