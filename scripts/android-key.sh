#!/bin/zsh
# Einmalig: eigenen Signierschlüssel für die Android-App anlegen und bei GitHub hinterlegen.
# Android installiert ein Update nur, wenn es mit demselben Schlüssel signiert ist wie die installierte App.
# Ohne diesen Schritt signiert GitHub jede APK mit einem anderen Testschlüssel – dann muss man die App vor
# jedem Update deinstallieren (und verliert die Daten auf dem Handy).
#
#   npm run android-key            → Schlüssel anlegen (falls noch keiner da ist) und zu GitHub hochladen
#
# Der Schlüssel liegt danach NUR auf diesem Mac (nicht im Projekt) und als geheimer Wert bei GitHub:
#   ~/Library/Application Support/Bogey Club Entwicklung/android.keystore (+ Passwort daneben)
# Bitte diesen Ordner sichern – geht er verloren, lassen sich Updates nicht mehr über die installierte App spielen.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/git-common.sh

DIR="$HOME/Library/Application Support/Bogey Club Entwicklung"
KEY="$DIR/android.keystore"
PASSFILE="$DIR/android.keystore.passwort"

require_gh
command -v keytool >/dev/null || fail "keytool fehlt (gehört zu Java): brew install openjdk"

if [[ -f "$KEY" ]]; then
  say "Vorhandenen Schlüssel verwenden: $KEY"
  [[ -f "$PASSFILE" ]] || fail "Das Passwort zum Schlüssel fehlt: $PASSFILE"
  PASS="$(cat "$PASSFILE")"
else
  say "Neuen Schlüssel anlegen"
  mkdir -p "$DIR"; chmod 700 "$DIR"
  PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
  keytool -genkeypair -noprompt -storetype PKCS12 -keystore "$KEY" -storepass "$PASS" -keypass "$PASS" \
    -alias bogeyclub -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Bogey Club, O=Marwaeck" >/dev/null 2>&1 \
    || fail "Der Schlüssel konnte nicht angelegt werden."
  print -rn -- "$PASS" > "$PASSFILE"; chmod 600 "$KEY" "$PASSFILE"
fi

say "Bei GitHub hinterlegen (geheim, nur für die automatischen Builds lesbar)"
base64 -i "$KEY" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64
print -rn -- "$PASS" | gh secret set ANDROID_KEYSTORE_PASSWORD
ok "Fertig. Ab dem nächsten Build ist die Android-App mit diesem Schlüssel signiert."
print -r -- "  Bitte den Ordner sichern: $DIR"
