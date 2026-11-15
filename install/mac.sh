#!/bin/zsh
# Bogey Club für den Mac installieren oder aktualisieren – ein Befehl im Terminal:
#   curl -fsSL https://raw.githubusercontent.com/Marwaeck/BogeyClub/main/install/mac.sh | zsh
# Lädt die neueste Mac-Version von GitHub (Releases), legt „Bogey Club.app“ in „Programme“ und startet sie.
# Deine Daten (~/Library/Application Support/Bogey Club) bleiben unberührt.
# Optional: BOGEY_ZIP=/pfad/Bogey-Club-mac-1.0.0.zip (lokale Datei statt Download), BOGEY_APPS_DIR=/anderer/ordner
set -euo pipefail

REPO="Marwaeck/BogeyClub"
APP_NAME="Bogey Club.app"
say() { print -r -- "→ $*"; }
fail() { print -r -- "✗ $*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "Dieses Skript ist für macOS."
autoload -Uz is-at-least
is-at-least 13 "$(sw_vers -productVersion)" || fail "Bogey Club braucht macOS 13 oder neuer."

WORK="$(mktemp -d -t bogeyclub)"
trap 'command rm -rf "$WORK"' EXIT

if [[ -n "${BOGEY_ZIP:-}" ]]; then
  [[ -f "$BOGEY_ZIP" ]] || fail "Datei nicht gefunden: $BOGEY_ZIP"
  cp "$BOGEY_ZIP" "$WORK/app.zip"
else
  say "Suche die neueste Version auf GitHub …"
  JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest")" \
    || fail "Noch keine Version veröffentlicht oder keine Verbindung zu GitHub."
  URL="$(print -r -- "$JSON" | grep -o '"browser_download_url": *"[^"]*Bogey-Club-mac-[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
  [[ -n "$URL" ]] || fail "In der neuesten Version fehlt die Mac-Datei (Bogey-Club-mac-….zip)."
  say "Lade ${URL##*/} …"
  curl -fL --progress-bar "$URL" -o "$WORK/app.zip" || fail "Download fehlgeschlagen."
fi

say "Entpacke …"
ditto -x -k "$WORK/app.zip" "$WORK/neu"
NEW="$WORK/neu/$APP_NAME"
[[ -d "$NEW" ]] || fail "Die ZIP enthält kein „$APP_NAME“."
codesign --verify --deep "$NEW" 2>/dev/null || fail "Die App ist beschädigt (Signatur passt nicht)."
VERSION="$(defaults read "$NEW/Contents/Info.plist" CFBundleShortVersionString)"

# Ziel: /Applications, wenn beschreibbar – sonst ~/Applications
DEST="${BOGEY_APPS_DIR:-/Applications}"
if [[ ! -w "$DEST" ]]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
TARGET="$DEST/$APP_NAME"

if pgrep -xq BogeyClub; then
  say "Beende die laufende App …"
  osascript -e 'tell application id "club.bogey.mac" to quit' >/dev/null 2>&1 || true
  for i in {1..20}; do pgrep -xq BogeyClub || break; sleep 0.5; done
fi

say "Installiere Bogey Club $VERSION nach $DEST …"
xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true   # selbst signiert: ohne Rückfrage von Gatekeeper starten
if [[ -e "$TARGET" ]]; then mv "$TARGET" "$WORK/alt.app"; fi
if ! ditto "$NEW" "$TARGET"; then
  [[ -e "$WORK/alt.app" ]] && mv "$WORK/alt.app" "$TARGET"
  fail "Konnte nicht nach $DEST schreiben."
fi

[[ -n "${BOGEY_NO_OPEN:-}" ]] || open "$TARGET"
print -r -- "✓ Bogey Club $VERSION ist installiert: $TARGET"
