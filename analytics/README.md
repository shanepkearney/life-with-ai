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

## Deploy

CI does it: `.github/workflows/analytics.yml` tests the Worker on every change to `analytics/`, and on `main`
uploads it with Wrangler (which needs Node 22) and checks it's live, without storing anything. It can also be
run by hand from the Actions tab ("Event collector" → Run workflow).

It needs two repository settings:

- `CLOUDFLARE_ACCOUNT_ID` (variable): the life-with-ai Cloudflare account's ID.
- `CLOUDFLARE_API_TOKEN` (secret): in the Cloudflare dashboard, **My Profile → API Tokens → Create Token →
  "Edit Cloudflare Workers"** template, limited to the life-with-ai account. Save it with
  `gh secret set CLOUDFLARE_API_TOKEN` and paste it when asked (never into a chat or a file).

The Worker lives at `https://life-with-ai-events.shane-kearney-pro.workers.dev/v1/event`. That's the app's
`TELEMETRY_URL` repository variable: until it's set, released builds send nothing.

## Tests

```
node --test analytics/test/*.test.js
```

CI runs them on every push and pull request.

## Reading the numbers

`tool/seed_stats.sh` asks the Analytics Engine SQL API which seeds were opened
most in the last N days. It needs an API token with **Account Analytics: Read**
(create one under My Profile → API Tokens) in `CLOUDFLARE_API_TOKEN`, and the
account ID in `CLOUDFLARE_ACCOUNT_ID`.
