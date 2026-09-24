#!/bin/bash
# Checks the live site right after a deploy, from the outside, the way a
# visitor sees it:
#
#   tool/smoke_live.sh <commit> [<version> <released>]
#
#   - the site serves the build of <commit> (Pages' cache can lag a few minutes,
#     so this waits for it),
#   - the Cloudflare analytics beacon is in the page,
#   - when <released> is "true": the v<version> release page exists and
#     …/releases/latest/download/Life-with-AI.dmg downloads a real disk image.
set -euo pipefail

commit="$1"
version="${2:-}"
released="${3:-false}"
site="https://shanepkearney.github.io/life-with-ai"
repo="https://github.com/shanepkearney/life-with-ai"

fail() { echo "::error::$*"; exit 1; }

# The commit is compiled into the app (APP_COMMIT), so it appears in main.dart.js.
for attempt in $(seq 1 40); do
  # Download first: grep -q would stop reading early and fail curl under pipefail.
  if curl -fsSL -o /tmp/main.dart.js "$site/main.dart.js?smoke=$attempt" && grep -q "$commit" /tmp/main.dart.js; then
    echo "✓ the site serves the build of $commit"
    break
  fi
  [ "$attempt" = 40 ] && fail "after 10 minutes the site still doesn't serve the build of $commit"
  sleep 15
done

curl -fsSL -o /tmp/index.html "$site/" || fail "the site doesn't load"
grep -q 'static.cloudflareinsights.com/beacon.min.js' /tmp/index.html || fail "the analytics beacon is missing from the page"
echo "✓ the analytics beacon is in the page"

if [ "$released" = true ]; then
  curl -fsSL -o /dev/null "$repo/releases/tag/v$version" || fail "no release page for v$version"
  echo "✓ the v$version release page exists"
  size=$(curl -fsSL -o /tmp/Life-with-AI.dmg -w '%{size_download}' "$repo/releases/latest/download/Life-with-AI.dmg") \
    || fail "the macOS download link doesn't resolve"
  [ "$size" -gt 5000000 ] || fail "the macOS download is only $size bytes"
  # A disk image ends in a "koly" trailer.
  tail -c 512 /tmp/Life-with-AI.dmg | head -c 4 | grep -q koly || fail "the macOS download isn't a disk image"
  echo "✓ the macOS download is a disk image ($((size / 1024 / 1024)) MB)"
fi
