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
trap 'rm -rf "$ROOT"' EXIT
ditto --noextattr --noqtn "$APP" "$ROOT/Nyx.app"
ln -s /Applications "$ROOT/Applications"
hdiutil create -quiet -volname "Nyx" -srcfolder "$ROOT" -fs HFS+ -format UDZO "$DMG"

echo "✓ $DMG"
