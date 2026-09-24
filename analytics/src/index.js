// Life with AI's event collector: one small Cloudflare Worker that accepts
// "seed_opened" events from the app and writes them to Workers Analytics
// Engine. It stores only what's listed below: never a seed's cells, its
// title (someone's prompt), or anything about the visitor beyond the platform.
//
//   POST /v1/event  {"event":"seed_opened","seed":"<12 hex>","source":"community",
//                    "name":"Oscillator Garden","version":"1.1.1","platform":"web"}
//
// Deploy: `npx wrangler deploy` from analytics/ (see analytics/README.md).

export const SOURCES = new Set(['share_link', 'community', 'favorite', 'assistant']);
export const PLATFORMS = new Set(['web', 'macos']);
const SITE = 'https://shanepkearney.github.io';
const MAX_BODY = 1024;

/** The event as the app sends it, validated, or null if anything is off. */
export function parseEvent(text) {
  if (typeof text !== 'string' || text.length > MAX_BODY) return null;
  let e;
  try {
    e = JSON.parse(text);
  } catch {
    return null;
  }
  if (!e || typeof e !== 'object' || Array.isArray(e)) return null;
  const allowed = new Set(['event', 'seed', 'source', 'name', 'version', 'platform']);
  if (Object.keys(e).some((k) => !allowed.has(k))) return null;
  if (e.event !== 'seed_opened') return null;
  if (typeof e.seed !== 'string' || !/^[0-9a-f]{12}$/.test(e.seed)) return null;
  if (!SOURCES.has(e.source) || !PLATFORMS.has(e.platform)) return null;
  if (typeof e.version !== 'string' || !/^\d+\.\d+\.\d+$/.test(e.version)) return null;
  // A name only for community seeds: those are public; other titles are people's prompts.
  if (e.name !== undefined) {
    if (e.source !== 'community' || typeof e.name !== 'string' || e.name.length > 40 || /[\u0000-\u001f]/.test(e.name)) return null;
  }
  return { seed: e.seed, source: e.source, name: e.name ?? '', version: e.version, platform: e.platform };
}

function cors(origin) {
  return {
    'Access-Control-Allow-Origin': origin === SITE ? SITE : 'null',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors(origin) });
    if (url.pathname !== '/v1/event' || request.method !== 'POST') return new Response('Not found', { status: 404 });
    // Browsers send the site's Origin; the macOS app sends none. Anything else isn't ours.
    if (origin !== null && origin !== SITE) return new Response('Forbidden', { status: 403 });

    const event = parseEvent(await request.text());
    if (!event) return new Response('Bad event', { status: 400, headers: cors(origin) });

    env.EVENTS.writeDataPoint({
      indexes: [event.seed],
      blobs: [event.seed, event.source, event.name, event.version, event.platform],
      doubles: [1],
    });
    return new Response(null, { status: 204, headers: cors(origin) });
  },
};
