import assert from 'node:assert/strict';
import { test } from 'node:test';

import worker, { parseEvent, parseError } from '../src/index.js';

const good = { event: 'seed_opened', seed: '0123456789ab', source: 'community', name: 'Oscillator Garden', version: '1.1.1', platform: 'web' };
const body = (e) => JSON.stringify(e);

test('a good event parses to exactly the stored fields', () => {
  assert.deepEqual(parseEvent(body(good)), { seed: '0123456789ab', source: 'community', name: 'Oscillator Garden', version: '1.1.1', platform: 'web' });
  const { name, ...shared } = good;
  assert.equal(parseEvent(body({ ...shared, source: 'share_link' })).name, '');
});

test('anything else is refused', () => {
  const bad = [
    'not json', '[]', 'null', 'x'.repeat(2000),
    body({ ...good, event: 'page_view' }),
    body({ ...good, seed: '1_512x384_216_152_b2o' }), // a seed's cells, not its fingerprint
    body({ ...good, seed: 'ABCDEF012345' }),
    body({ ...good, source: 'twitter' }),
    body({ ...good, platform: 'windows' }),
    body({ ...good, version: 'dev' }),
    body({ ...good, title: 'someone’s prompt' }), // unknown field
    body({ ...good, source: 'share_link', name: 'A prompt' }), // names only for community seeds
    body({ ...good, name: 'x'.repeat(41) }),
  ];
  for (const b of bad) assert.equal(parseEvent(b), null, b.slice(0, 60));
});

function request(method, path, { origin, text } = {}) {
  const headers = new Headers();
  if (origin) headers.set('Origin', origin);
  return new Request(`https://events.example${path}`, { method, headers, body: text });
}

test('the worker stores good events from the site or the app, and nothing else', async () => {
  const points = [];
  const env = { EVENTS: { writeDataPoint: (p) => points.push(p) } };

  let r = await worker.fetch(request('POST', '/v1/event', { origin: 'https://shanepkearney.github.io', text: body(good) }), env);
  assert.equal(r.status, 204);
  assert.equal(r.headers.get('Access-Control-Allow-Origin'), 'https://shanepkearney.github.io');
  r = await worker.fetch(request('POST', '/v1/event', { text: body({ ...good, platform: 'macos' }) }), env); // the macOS app: no Origin
  assert.equal(r.status, 204);
  assert.deepEqual(points.map((p) => p.blobs[4]), ['web', 'macos']);
  assert.deepEqual(points[0].indexes, ['0123456789ab']);

  assert.equal((await worker.fetch(request('POST', '/v1/event', { origin: 'https://evil.example', text: body(good) }), env)).status, 403);
  assert.equal((await worker.fetch(request('POST', '/v1/event', { text: 'nope' }), env)).status, 400);
  assert.equal((await worker.fetch(request('GET', '/v1/event'), env)).status, 404);
  assert.equal((await worker.fetch(request('POST', '/elsewhere', { text: body(good) }), env)).status, 404);
  assert.equal((await worker.fetch(request('OPTIONS', '/v1/event', { origin: 'https://shanepkearney.github.io' }), env)).status, 204);
  assert.equal(points.length, 2, 'nothing else was stored');
});

const error = { event: 'app_error', kind: 'load', message: 'Failed to fetch dynamically imported module', browser: 'facebook', version: '1.14.0', platform: 'web' };

test('a good app error parses to exactly the stored fields', () => {
  assert.deepEqual(parseError(body(error)), { kind: 'load', message: 'Failed to fetch dynamically imported module', browser: 'facebook', version: '1.14.0' });
  assert.equal(parseEvent(body(error)), null, 'an error is not a seed event');
  assert.equal(parseError(body(good)), null, 'nor a seed event an error');
});

test('app errors are refused unless every field is as expected', () => {
  const bad = [
    body({ ...error, kind: 'crash' }),
    body({ ...error, browser: 'Mozilla/5.0 (Linux; Android 14)' }), // never a user agent
    body({ ...error, platform: 'macos' }),
    body({ ...error, version: 'dev' }),
    body({ ...error, message: 'x'.repeat(201) }),
    body({ ...error, message: 'at https://shanepkearney.github.io/life-with-ai/#seed=1_512x384' }), // a URL could carry a seed
    body({ ...error, message: 'two\nlines' }),
    body({ ...error, stack: 'at foo' }), // unknown field
  ];
  for (const b of bad) assert.equal(parseError(b), null, b.slice(0, 80));
});

test('an app error is stored in its own dataset', async () => {
  const events = [], errors = [];
  const env = { EVENTS: { writeDataPoint: (p) => events.push(p) }, ERRORS: { writeDataPoint: (p) => errors.push(p) } };
  const res = await worker.fetch(new Request('https://x/v1/event', { method: 'POST', body: body(error), headers: { Origin: 'https://shanepkearney.github.io' } }), env);
  assert.equal(res.status, 204);
  assert.equal(events.length, 0);
  assert.deepEqual(errors[0].blobs, ['load', 'facebook', '1.14.0', 'Failed to fetch dynamically imported module']);
});
