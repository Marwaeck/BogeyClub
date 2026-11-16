#!/bin/zsh
# Aktualisieren: alle Änderungen speichern (commit) und zu GitHub hochladen (push) – ohne neue App-Version.
# Danach aktualisieren sich von selbst: die Web-App auf Cloudflare (Workers Builds) und die Website (GitHub Pages).
# Mac- und Windows-App bekommen ein Update erst mit einer neuen Version (scripts/release.sh).
#
#   npm run upload                    → fragt, was geändert wurde
#   npm run upload -- "Text"          → Beschreibung direkt angeben
#   npm run upload -- --probe         → nur anzeigen, was passieren würde (ändert nichts)
#
# Braucht: Git mit Zugriff auf GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/git-common.sh

PROBE=0; MESSAGE=""
for a in "$@"; do
  case "$a" in
    --probe|--dry-run) PROBE=1 ;;
    *) MESSAGE="$a" ;;
  esac
done

require_git
CHANGES="$(pending_changes)"

if [[ $PROBE -eq 1 ]]; then
  check_github
  say "Probelauf – es wird nichts verändert."
  (( BEHIND > 0 )) && say "Würde zuerst ${BEHIND} neuere Speicherung(en) von GitHub übernehmen."
  if [[ -n "$CHANGES" ]]; then
    say "Würde speichern und hochladen:"; print -r -- "$CHANGES" | sed 's/^/    /'
  elif (( AHEAD > 0 )); then
    say "Würde ${AHEAD} schon gespeicherte, aber noch nicht hochgeladene Speicherung(en) hochladen."
  else
    say "Nichts zu tun – alles ist schon auf GitHub."
  fi
  exit 0
fi

sync_with_github

if [[ -n "$CHANGES" ]]; then
  print -r -- "Geänderte Dateien:"; print -r -- "$CHANGES" | sed 's/^/    /'
  if [[ -z "$MESSAGE" ]]; then
    print -r -- "Was hast du geändert? (eine Zeile, Eingabetaste für „Aktualisiert“)"
    read -r MESSAGE || true
  fi
  [[ -n "$MESSAGE" ]] || MESSAGE="Aktualisiert am $(date '+%d.%m.%Y %H:%M')"
  [[ -f build.mjs ]] && { say "Web-Version bauen"; npm run build --silent >/dev/null; }
  say "Speichern (commit)"
  stage_all
  git diff --cached --quiet || git commit -q -m "$MESSAGE"
fi

check_github
if (( AHEAD == 0 )); then
  ok "Nichts zu tun – alles ist schon auf GitHub."
  exit 0
fi

say "Hochladen (push)"
git push -q origin main || fail "Hochladen hat nicht geklappt. Die Speicherung bleibt hier erhalten – einfach noch einmal starten."
ok "Hochgeladen: $(repo_url)"
print -r -- "  Web-App und Website aktualisieren sich in ein paar Minuten von selbst."
print -r -- "  Mac- und Windows-App bekommen das Update erst mit einer neuen Version."
