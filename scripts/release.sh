#!/bin/zsh
# Alles auf einmal: speichern (commit), hochladen (push) und eine neue Version veröffentlichen (GitHub-Release
# mit Mac- und Windows-App – die Updater in den Apps finden sie dort).
#
#   npm run release                         → nächste kleine Version (1.0.0 → 1.0.1), fragt nach den Neuerungen
#   npm run release -- minor "Neu: …"       → 1.0.x → 1.1.0, Neuerungen direkt angeben
#   npm run release -- 2.0.0 "…"            → genau diese Version
#   npm run release -- --probe              → nur anzeigen, was passieren würde (ändert nichts)
#
# Die allererste Veröffentlichung nimmt die Version aus package.json, wie sie ist (1.0.0).
# Braucht: Git mit Zugriff auf GitHub, die GitHub-CLI „gh“ (angemeldet: gh auth login), Xcode und Node.
set -euo pipefail
cd "$(dirname "$0")/.."

say() { print -r -- "→ $*"; }
fail() { print -r -- "✗ $*" >&2; exit 1; }

PROBE=0; BUMP="patch"; NOTES=""
for a in "$@"; do
  case "$a" in
    --probe|--dry-run) PROBE=1 ;;
    patch|minor|major|[0-9]*.[0-9]*.[0-9]*) BUMP="$a" ;;
    *) NOTES="$a" ;;
  esac
done

command -v gh >/dev/null || fail "Die GitHub-CLI „gh“ fehlt: brew install gh, dann gh auth login."
gh auth status >/dev/null 2>&1 || fail "Bei GitHub nicht angemeldet: gh auth login"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "Bitte auf dem Zweig „main“ arbeiten."

# ---- Version bestimmen ----
CURRENT="$(node -p "require('./package.json').version")"
LATEST_TAG="$(gh release view --json tagName -q .tagName 2>/dev/null || true)"
if [[ -z "$LATEST_TAG" && "$BUMP" == "patch" ]]; then
  VERSION="$CURRENT"                                       # erste Veröffentlichung
else
  VERSION="$(node -e '
    const [cur, bump] = process.argv.slice(1);
    if (/^\d+\.\d+\.\d+$/.test(bump)) { console.log(bump); process.exit(0); }
    let [a, b, c] = cur.split(".").map(Number);
    if (bump === "major") { a++; b = 0; c = 0; } else if (bump === "minor") { b++; c = 0; } else { c++; }
    console.log([a, b, c].join("."));' "$CURRENT" "$BUMP")"
fi
TAG="v${VERSION}"
gh release view "$TAG" >/dev/null 2>&1 && fail "Version ${VERSION} ist schon veröffentlicht."

if [[ -z "$NOTES" && $PROBE -eq 0 ]]; then
  print -r -- "Was ist neu in Bogey Club ${VERSION}? (eine Zeile pro Punkt, zum Abschließen eine leere Zeile)"
  while IFS= read -r line; do [[ -z "$line" ]] && break; NOTES+="- ${line}"$'\n'; done
fi
[[ -n "$NOTES" ]] || NOTES="Bogey Club ${VERSION}"

if [[ $PROBE -eq 1 ]]; then
  say "Probelauf – es wird nichts verändert."
  say "Version: ${CURRENT} → ${VERSION} (Release ${TAG}, letztes Release: ${LATEST_TAG:-keins})"
  say "Würde speichern und hochladen:"; git status --short | sed 's/^/    /'
  say "Würde bauen: mac/build/Bogey-Club-mac-${VERSION}.zip und windows/dist/Bogey-Club-windows-${VERSION}.zip"
  say "Neuerungen: ${NOTES}"
  exit 0
fi

# ---- 1. Version eintragen, speichern, hochladen ----
say "Version ${VERSION} eintragen"
node -e '
  const fs = require("fs"), v = process.argv[1];
  for (const f of ["package.json", "windows/package.json"]) {
    const j = JSON.parse(fs.readFileSync(f, "utf8")); j.version = v;
    fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n");
  }' "$VERSION"
npm run build --silent >/dev/null                        # Web-Version (public/) auf den aktuellen Stand bringen

say "Speichern (commit)"
git add -A
if ! git diff --cached --quiet; then git commit -q -m "Bogey Club ${VERSION}" -m "$NOTES"; fi
say "Hochladen (push)"
git push -q origin main

# ---- 2. Apps bauen ----
say "Mac-App bauen";     ./mac/build.sh
say "Windows-App bauen"; npm --prefix windows install --no-audit --no-fund --silent && npm --prefix windows run dist --silent

# ---- 3. Veröffentlichen ----
say "Veröffentlichen (GitHub-Release ${TAG})"
gh release create "$TAG" \
  "mac/build/Bogey-Club-mac-${VERSION}.zip" \
  "windows/dist/Bogey-Club-windows-${VERSION}.zip" \
  --title "Bogey Club ${VERSION}" --notes "$NOTES" --target "$(git rev-parse HEAD)"

print -r -- "✓ Bogey Club ${VERSION} ist hochgeladen und veröffentlicht."
print -r -- "  Die Apps bieten das Update beim nächsten Start an; neu installieren geht mit den Befehlen in der README."
