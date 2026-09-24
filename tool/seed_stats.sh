#!/bin/bash
# Which seeds were opened most, from the seed-open events (analytics/README.md).
#
#   CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=… tool/seed_stats.sh [days]
set -euo pipefail

days="${1:-7}"
[[ "$days" =~ ^[0-9]+$ ]] || { echo "days must be a number" >&2; exit 64; }
: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN (Account Analytics: Read)}"
: "${CLOUDFLARE_ACCOUNT_ID:?set CLOUDFLARE_ACCOUNT_ID}"

query="SELECT blob1 AS seed, blob3 AS name, blob2 AS source, blob5 AS platform, SUM(_sample_interval) AS opens
FROM life_with_ai_events
WHERE timestamp > NOW() - INTERVAL '$days' DAY
GROUP BY seed, name, source, platform
ORDER BY opens DESC
LIMIT 50
FORMAT TabSeparatedWithNames"

curl -fsS "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/analytics_engine/sql" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" --data-binary "$query" | column -t -s $'\t'
