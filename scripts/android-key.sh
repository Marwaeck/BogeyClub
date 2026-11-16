#!/bin/zsh
# Einmalig: eigenen Signierschlüssel für die Android-App anlegen und bei GitHub hinterlegen.
# Android installiert ein Update nur, wenn es mit demselben Schlüssel signiert ist wie die installierte App.
# Ohne diesen Schritt signiert GitHub jede APK mit einem anderen Testschlüssel – dann muss man die App vor
# jedem Update deinstallieren (und verliert die Daten auf dem Handy).
#
#   npm run android-key            → Schlüssel anlegen (falls noch keiner da ist) und zu GitHub hochladen
#   npm run android-key -- --probe → nur ausprobieren: Schlüssel im Wegwerf-Ordner, nichts zu GitHub
#
# Der Schlüssel liegt danach NUR auf diesem Mac (nicht im Projekt) und als geheimer Wert bei GitHub:
#   ~/Library/Application Support/Bogey Club Entwicklung/android.keystore (+ Passwort daneben)
# Bitte diesen Ordner sichern – geht er verloren, lassen sich Updates nicht mehr über die installierte App spielen.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/git-common.sh

PROBE=0; [[ "${1:-}" == "--probe" ]] && PROBE=1

DIR="$HOME/Library/Application Support/Bogey Club Entwicklung"
(( PROBE )) && DIR="$(mktemp -d)"
KEY="$DIR/android.keystore"
PASSFILE="$DIR/android.keystore.passwort"

(( PROBE )) || require_gh

# Der Schlüssel entsteht mit OpenSSL (gehört zu macOS) – Java ist dafür nicht nötig. Ergebnis ist ein
# PKCS12-Schlüsselbund mit dem Eintrag „bogeyclub“, den Gradle beim Bauen der APK direkt liest.
command -v openssl >/dev/null || fail "openssl fehlt."

if [[ -f "$KEY" && -f "$PASSFILE" ]]; then
  say "Vorhandenen Schlüssel verwenden: $KEY"
  PASS="$(<"$PASSFILE")"
else
  # Rest eines abgebrochenen Versuchs ohne Passwort ist unbrauchbar – beiseitelegen statt überschreiben
  [[ -f "$KEY" ]] && mv "$KEY" "$KEY.unvollstaendig-$(date +%Y%m%d%H%M%S)"
  say "Neuen Schlüssel anlegen"
  mkdir -p "$DIR"; chmod 700 "$DIR"
  # Zufallspasswort. Früher über „tr < /dev/urandom | head“ – das bricht wegen pipefail still ab.
  PASS="$(node -e 'process.stdout.write(require("crypto").randomBytes(24).toString("hex"))' 2>/dev/null || openssl rand -hex 24)"
  [[ ${#PASS} -ge 32 ]] || fail "Es konnte kein Passwort erzeugt werden."
  WORK="$(mktemp -d)"
  if ! OUT="$(openssl req -x509 -newkey rsa:4096 -sha256 -days 10000 -nodes -subj "/CN=Bogey Club/O=Marwaeck" \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>&1 \
      && openssl pkcs12 -export -name bogeyclub -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$KEY" -passout "pass:$PASS" 2>&1)"; then
    rm -rf "$WORK" "$KEY"
    fail "Der Schlüssel konnte nicht angelegt werden: $OUT"
  fi
  rm -rf "$WORK"
  print -rn -- "$PASS" > "$PASSFILE"; chmod 600 "$KEY" "$PASSFILE"
fi

openssl pkcs12 -in "$KEY" -passin "pass:$PASS" -nokeys -noout >/dev/null 2>&1 \
  || fail "Der Schlüssel lässt sich mit dem gespeicherten Passwort nicht öffnen: $KEY"
ok "Schlüssel ist in Ordnung."

if (( PROBE )); then
  say "Probelauf – nichts wurde zu GitHub hochgeladen. (Wegwerf-Ordner: $DIR)"
  exit 0
fi

say "Bei GitHub hinterlegen (geheim, nur für die automatischen Builds lesbar)"
base64 -i "$KEY" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 \
  || fail "Hochladen zu GitHub hat nicht geklappt (gh auth status prüfen) – einfach noch einmal starten."
print -rn -- "$PASS" | gh secret set ANDROID_KEYSTORE_PASSWORD \
  || fail "Hochladen zu GitHub hat nicht geklappt (gh auth status prüfen) – einfach noch einmal starten."
gh secret list 2>/dev/null | grep -q '^ANDROID_KEYSTORE_BASE64' || fail "GitHub zeigt den Schlüssel nicht an – bitte noch einmal starten."
ok "Fertig. Ab dem nächsten Build ist die Android-App mit diesem Schlüssel signiert."
print -r -- "  Bitte den Ordner sichern: $DIR"
print -r -- "  Eine schon installierte Android-App (mit Testschlüssel) einmal löschen und die neue APK installieren –"
print -r -- "  vorher in der App „Spieler → Daten-Backup“ herunterladen und danach wieder einspielen."
