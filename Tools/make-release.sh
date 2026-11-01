#!/bin/zsh
# Builds dist/Nyx-<version>.dmg on this Mac, with no GitHub Actions involved.
#
# Nyx is signed with the local "Nyx Utils Signing" identity, not an Apple
# Developer ID, so a downloaded copy needs "Open Anyway" in System Settings
# once. Share the .dmg directly, or attach it to a GitHub release by hand:
#   gh release create v<version> dist/Nyx-<version>.dmg -R Aareevs/Nyx
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
APP="build/stage/Nyx.app"
DMG="dist/Nyx-$VERSION.dmg"

echo "▸ Building Nyx $VERSION…"
./build.sh

echo "▸ Packaging $DMG…"
mkdir -p dist
rm -f "$DMG"
ROOT=$(mktemp -d)
RW="$ROOT/rw.dmg"
trap 'hdiutil detach "/Volumes/Nyx" >/dev/null 2>&1 || true; rm -rf "$ROOT"' EXIT
hdiutil detach "/Volumes/Nyx" >/dev/null 2>&1 || true

# Stage the window contents: the app (Finder adds an Applications alias) and the
# background picture drawn by Tools/dmg/make-background.py.
STAGE="$ROOT/stage"
mkdir -p "$STAGE/.background"
ditto --noextattr --noqtn "$APP" "$STAGE/Nyx.app"
cp Tools/dmg/background.tiff "$STAGE/.background/background.tiff"
hdiutil create -quiet -volname "Nyx" -srcfolder "$STAGE" -fs HFS+ -format UDRW "$RW"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint /Volumes/Nyx "$RW"

# Lay the window out with Finder. This opens the window for a moment and may
# ask once to let Terminal control Finder.
osascript <<'OSA' || echo "  (could not style the DMG window; it will open with the plain layout)"
tell application "Finder"
    tell disk "Nyx"
        open
        make new alias file at container window to POSIX file "/Applications" with properties {name:"Applications"}
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 580}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Nyx.app" of container window to {320, 225}
        set position of item "Applications" of container window to {545, 225}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
OSA
sync
hdiutil detach -quiet /Volumes/Nyx
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"

echo "✓ $DMG"
