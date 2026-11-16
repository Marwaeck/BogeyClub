#!/bin/zsh
# Gemeinsame Bausteine für scripts/upload.sh und scripts/release.sh (wird mit „source“ geladen).

say() { print -r -- "→ $*"; }
ok() { print -r -- "✓ $*"; }
fail() { print -r -- "✗ $*" >&2; exit 1; }

# Arbeitsdateien von Craft Anything liegen im Projektordner, gehören aber nicht auf GitHub.
NOT_UPLOADED=(
  craft.json feed.json questions.json usage.json assets.json transcript.json extract-transcript.json
  agent-session.jsonl build-activity.log build-activity.old.log
  inbox checks capture reference attachments investigation.cany pinned
)
EXCLUDES=()
for p in "${NOT_UPLOADED[@]}"; do EXCLUDES+=(":(top,exclude)$p"); done

require_git() {
  command -v git >/dev/null || fail "Git fehlt: xcode-select --install"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Dieser Ordner ist kein Git-Projekt."
  git remote get-url origin >/dev/null 2>&1 || fail "Keine Verbindung zu GitHub eingerichtet (git remote „origin“ fehlt)."
  [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "Bitte auf dem Zweig „main“ arbeiten (gerade: $(git rev-parse --abbrev-ref HEAD))."
  [[ -d "$(git rev-parse --git-dir)/rebase-merge" || -d "$(git rev-parse --git-dir)/rebase-apply" ]] \
    && fail "Ein früheres Zusammenführen ist nicht abgeschlossen. Erst „git rebase --continue“ oder „git rebase --abort“."
  return 0
}

require_gh() {
  command -v gh >/dev/null || fail "Die GitHub-CLI „gh“ fehlt: brew install gh, dann gh auth login."
  gh auth status >/dev/null 2>&1 || fail "Bei GitHub nicht angemeldet: gh auth login"
}

# Holt den Stand von GitHub. Setzt BEHIND (Speicherungen nur auf GitHub) und AHEAD (nur hier).
check_github() {
  git fetch -q origin main 2>/dev/null || fail "GitHub ist nicht erreichbar (Internet? Anmeldung?)."
  BEHIND="$(git rev-list --count HEAD..origin/main)"
  AHEAD="$(git rev-list --count origin/main..HEAD)"
}

# Übernimmt Änderungen, die schon auf GitHub sind (z. B. im Browser bearbeitet), bevor hochgeladen wird.
sync_with_github() {
  check_github
  if (( BEHIND > 0 )); then
    say "Auf GitHub gibt es ${BEHIND} neuere Speicherung(en) – werden zuerst übernommen"
    git pull -q --rebase --autostash origin main \
      || fail "Die Änderungen hier und auf GitHub widersprechen sich. Bitte in GitHub Desktop oder mit „git status“ klären."
  fi
}

# Alle Änderungen vormerken – ohne die Arbeitsdateien von Craft Anything.
stage_all() { git add -A -- . "${EXCLUDES[@]}"; }

# Zeigt, was gespeichert würde (ohne die Arbeitsdateien von Craft Anything).
pending_changes() { git -c core.quotepath=false status --short --untracked-files=all -- . "${EXCLUDES[@]}"; }

repo_url() {
  local url; url="$(git remote get-url origin)"
  url="${url%.git}"; url="${url/git@github.com:/https://github.com/}"
  print -r -- "$url"
}
