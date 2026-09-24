# Seed-open events

A small Cloudflare Worker (`src/index.js`) that the released app tells whenever
a seed is opened, so we can see which seeds people play. It writes one row per
event to Workers Analytics Engine (dataset `life_with_ai_events`).

## What's stored

| Column | What | Example |
|---|---|---|
| `blob1` (also `index1`) | a 12-character fingerprint of the seed: never its cells | `3f9a1c0b77de` |
| `blob2` | where it was opened from | `share_link`, `community`, `favorite`, `assistant` |
| `blob3` | the community seed's name, for community seeds only (other titles are people's prompts, so never) | `Oscillator Garden` |
| `blob4` | app version | `1.1.1` |
| `blob5` | platform | `web`, `macos` |

Nothing else: no IP address, no cookie, no visitor ID. The Worker accepts events
only from the live site (or the macOS app, which sends no `Origin`), and refuses
anything that doesn't match the fields above exactly (see `test/`).

## Deploy (once, and whenever `src/` changes)

```
cd analytics
npx wrangler login     # opens your browser: approve in the life-with-ai Cloudflare account
npx wrangler deploy    # prints the Worker's address
```

Then set the repository variable the app builds with, so released builds start
sending (local builds never do):

```
gh variable set TELEMETRY_URL --body "https://life-with-ai-events.<your-subdomain>.workers.dev/v1/event"
```

## Tests

```
node --test analytics/test/
```

CI runs them on every push and pull request.

## Reading the numbers

`tool/seed_stats.sh` asks the Analytics Engine SQL API which seeds were opened
most in the last N days. It needs an API token with **Account Analytics: Read**
(create one under My Profile → API Tokens) in `CLOUDFLARE_API_TOKEN`, and the
account ID in `CLOUDFLARE_ACCOUNT_ID`.
