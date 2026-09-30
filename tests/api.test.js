'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('../api/_lib/core');

const TRANSCRIPT = 'Maya said photosynthesis makes energy from sunlight. There are five steps in the cycle. Remember to submit the worksheet Friday.';

const modelJson = (over = {}) => ({
  title: 'Bio',
  summary: 'Plants make energy. It takes 99 steps.',
  points: ['Photosynthesis makes energy.', 'There are 42 steps.', 'Five steps exist.'],
  actions: [
    { text: 'Submit the worksheet Friday.', owner: 'Maya' },
    { text: 'Email Priya.', owner: 'Priya' },
    { text: 'Pay $300.' },
  ],
  topics: [{ name: 'Plants', relatedPoints: [0, 1, 2, 9] }],
  links: [
    { from: 0, to: 2, label: 'leads to' },
    { from: 0, to: 1, label: 'drops with point' },
    { from: 2, to: 2, label: 'self' },
  ],
  ...over,
});
const okResponse = (obj = modelJson()) => ({
  status: 200,
  json: async () => ({ candidates: [{ content: { parts: [{ text: JSON.stringify(obj) }] } }] }),
});
const status = (s) => ({ status: s, json: async () => ({}) });

function fakeRes() {
  return {
    code: 0, body: undefined, headers: {},
    setHeader(k, v) { this.headers[k] = v; },
    status(c) { this.code = c; return this; },
    json(b) { this.body = b; return this; },
    end() { return this; },
  };
}

test('keyOrder rotates round-robin across requests', () => {
  core._setCursor(0);
  const keys = ['a', 'b', 'c'];
  assert.deepEqual(core.keyOrder(keys), ['a', 'b', 'c']);
  assert.deepEqual(core.keyOrder(keys), ['b', 'c', 'a']);
  assert.deepEqual(core.keyOrder(keys), ['c', 'a', 'b']);
  assert.deepEqual(core.keyOrder(keys), ['a', 'b', 'c']);
});

test('parseKeys splits and trims a comma-separated env var', () => {
  assert.deepEqual(core.parseKeys(' k1, k2 ,,k3 '), ['k1', 'k2', 'k3']);
  assert.deepEqual(core.parseKeys(undefined), []);
});

test('retries the next key on 429 and 5xx, then succeeds', async () => {
  core._setCursor(0);
  const used = [];
  const responses = [status(429), status(503), okResponse()];
  const fetchImpl = async (_url, opts) => {
    used.push(opts.headers['x-goog-api-key']);
    return responses.shift();
  };
  const out = await core.summarize(TRANSCRIPT, { keys: ['a', 'b', 'c'], fetchImpl });
  assert.deepEqual(used, ['a', 'b', 'c']);
  assert.equal(out.title, 'Bio');
});

test('key goes in a header, never the URL', async () => {
  core._setCursor(0);
  let url;
  await core.summarize(TRANSCRIPT, { keys: ['secret-key'], fetchImpl: async (u) => ((url = u), okResponse()) });
  assert.ok(!url.includes('secret-key'));
});

test('a network failure rotates to the next key', async () => {
  core._setCursor(0);
  let n = 0;
  const fetchImpl = async () => {
    if (n++ === 0) throw new Error('boom');
    return okResponse();
  };
  const out = await core.summarize(TRANSCRIPT, { keys: ['a', 'b'], fetchImpl });
  assert.equal(n, 2);
  assert.ok(out.points.length);
});

test('a non-retryable 400 stops immediately', async () => {
  core._setCursor(0);
  let calls = 0;
  await assert.rejects(
    core.summarize(TRANSCRIPT, { keys: ['a', 'b'], fetchImpl: async () => (calls++, status(400)) }),
    (e) => e.status === 502 && e.code === 'upstream_rejected'
  );
  assert.equal(calls, 1);
});

test('all keys failing reports quota or unavailable', async () => {
  core._setCursor(0);
  await assert.rejects(core.summarize(TRANSCRIPT, { keys: ['a', 'b'], fetchImpl: async () => status(429) }), (e) => e.status === 429);
  await assert.rejects(core.summarize(TRANSCRIPT, { keys: ['a', 'b'], fetchImpl: async () => status(500) }), (e) => e.status === 503);
});

test('malformed model output is a 502', async () => {
  core._setCursor(0);
  const bad = { status: 200, json: async () => ({ candidates: [{ content: { parts: [{ text: 'not json' }] } }] }) };
  await assert.rejects(core.summarize(TRANSCRIPT, { keys: ['a'], fetchImpl: async () => bad }), (e) => e.code === 'bad_model_output');
});

test('validate drops ungrounded numbers, unspoken owners and bad indexes', () => {
  const v = core.validate(modelJson(), TRANSCRIPT);
  // "42 steps" was never said; "Five" was spoken so it is kept.
  assert.deepEqual(v.points, ['Photosynthesis makes energy.', 'Five steps exist.']);
  // Indexes are remapped after the drop; index 9 and self-link are gone; link to the dropped point is gone.
  assert.deepEqual(v.topics, [{ name: 'Plants', relatedPoints: [0, 1] }]);
  assert.deepEqual(v.links, [{ from: 0, to: 1, label: 'leads to' }]);
  // "$300" is ungrounded; Priya was never spoken; Maya was.
  assert.deepEqual(v.actions, [{ text: 'Submit the worksheet Friday.', owner: 'Maya' }, { text: 'Email Priya.' }]);
  // Summary sentence with "99" removed.
  assert.equal(v.summary, 'Plants make energy.');
});

test('rate limiter blocks after the per-minute limit and recovers', () => {
  const check = core.createRateLimiter({ perMinute: 2, perDay: 100 });
  assert.equal(check('ip', 0).ok, true);
  assert.equal(check('ip', 1000).ok, true);
  const blocked = check('ip', 2000);
  assert.equal(blocked.ok, false);
  assert.ok(blocked.retryAfter > 0);
  assert.equal(check('other', 2000).ok, true);
  assert.equal(check('ip', 61000).ok, true);
});

test('handler: method, config, validation and length limits', async () => {
  const env = { GEMINI_KEYS: 'a,b' };
  const handler = core.makeHandler({ env, fetchImpl: async () => okResponse(), limiter: () => ({ ok: true }) });
  const call = async (req) => {
    const res = fakeRes();
    await handler({ headers: {}, ...req }, res);
    return res;
  };
  assert.equal((await call({ method: 'GET' })).code, 405);
  assert.equal((await call({ method: 'OPTIONS' })).code, 204);
  assert.equal((await call({ method: 'POST', body: { transcript: '   ' } })).code, 400);
  const long = await call({ method: 'POST', body: { transcript: 'x'.repeat(core.MAX_TRANSCRIPT + 1) } });
  assert.equal(long.code, 413);
  const good = await call({ method: 'POST', body: JSON.stringify({ transcript: TRANSCRIPT }) });
  assert.equal(good.code, 200);
  assert.deepEqual(Object.keys(good.body).sort(), ['actions', 'links', 'points', 'summary', 'title', 'topics']);

  const unconfigured = core.makeHandler({ env: {}, fetchImpl: async () => okResponse() });
  const res = fakeRes();
  await unconfigured({ method: 'POST', headers: {}, body: { transcript: 'hi' } }, res);
  assert.equal(res.code, 503);
});

test('handler: rate limit returns 429 with Retry-After, errors never leak keys', async () => {
  const limited = core.makeHandler({ env: { GEMINI_KEYS: 'secret-1' }, fetchImpl: async () => okResponse(), limiter: () => ({ ok: false, retryAfter: 30 }) });
  let res = fakeRes();
  await limited({ method: 'POST', headers: {}, body: { transcript: 'hi' } }, res);
  assert.equal(res.code, 429);
  assert.equal(res.headers['Retry-After'], '30');

  const failing = core.makeHandler({ env: { GEMINI_KEYS: 'secret-1' }, fetchImpl: async () => status(500), limiter: () => ({ ok: true }) });
  res = fakeRes();
  await failing({ method: 'POST', headers: {}, body: { transcript: 'hi there' } }, res);
  assert.equal(res.code, 503);
  assert.ok(!JSON.stringify(res.body).includes('secret-1'));
});
