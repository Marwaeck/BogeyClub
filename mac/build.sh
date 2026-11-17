#!/bin/zsh
# Baut „Bogey Club.app“ für den Mac nach mac/build/. Braucht Xcode (oder die Command Line Tools) und Node.
# Aufruf aus dem Projektordner:  ./mac/build.sh      (oder: npm run mac)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(node -p "require('../package.json').version")"   # eine Versionsnummer für alle Apps (package.json im Projektordner)
APP="build/Bogey Club.app"

echo "→ Web-Oberfläche vorbereiten"
node prepare-web.mjs

echo "→ App übersetzen"
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release -debug-info-format none "${ARCHS[@]}" >/dev/null 2>build/swift-universal.log; then
  echo "  (Universal-Build nicht möglich, baue nur für diesen Mac – Details: mac/build/swift-universal.log)"
  ARCHS=()
  swift build -c release -debug-info-format none
fi
BIN="$(swift build -c release -debug-info-format none "${ARCHS[@]}" --show-bin-path)/BogeyClub"

echo "→ App-Paket zusammenstellen"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BogeyClub"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R build/web "$APP/Contents/Resources/web"
mkdir -p "$APP/Contents/Resources/Lizenzen"
cp ../LICENSE "$APP/Contents/Resources/Lizenzen/LICENSE.txt"
cp ../THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/Lizenzen/Drittanbieter.txt"
cp ../licenses/*.txt "$APP/Contents/Resources/Lizenzen/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bogey Club</string>
  <key>CFBundleDisplayName</key><string>Bogey Club</string>
  <key>CFBundleIdentifier</key><string>club.bogey.mac</string>
  <key>CFBundleExecutable</key><string>BogeyClub</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.sports</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>UTExportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>club.bogey.file</string>
    <key>UTTypeDescription</key><string>Bogey-Club-Datei</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.content</string></array>
    <key>UTTypeIconFile</key><string>AppIcon</string>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>bogey</string></array>
      <key>public.mime-type</key><array><string>application/vnd.bogeyclub</string></array>
    </dict>
  </dict></array>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Bogey-Club-Datei</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>club.bogey.file</string></array>
    <key>CFBundleTypeIconFile</key><string>AppIcon</string>
  </dict></array>
  <key>NSHumanReadableCopyright</key><string>© 2026 Marwaeck. Alle Rechte vorbehalten.</string>
</dict>
</plist>
PLIST

echo "→ Signieren (lokal)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "→ ZIP für Downloads und Updater"
ZIP="build/Bogey-Club-mac-${VERSION}.zip"
ditto -c -k --keepParent "$APP" "$ZIP.tmp" && mv -f "$ZIP.tmp" "$ZIP"

echo "Fertig: mac/$APP (Version ${VERSION}) und mac/$ZIP"
