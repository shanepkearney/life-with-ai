#!/bin/bash
# Packs the release macOS app into a drag-to-install disk image: the app beside
# a link to /Applications.
#
#   tool/make_dmg.sh "build/macos/Build/Products/Release/Life with AI.app" Life-with-AI.dmg
#
# The app is only ad-hoc signed (no Apple Developer ID yet), so macOS asks the
# user to allow it once: see "Installing on macOS" in the README.
set -euo pipefail

app="$1"
out="$2"
[ -d "$app" ] || { echo "no app at $app" >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

rm -f "$out"
hdiutil create -volname "Life with AI" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$out" >/dev/null
hdiutil verify "$out" >/dev/null
echo "$out ($(du -h "$out" | cut -f1))"
