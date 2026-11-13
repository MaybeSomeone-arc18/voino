'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler } = require('../api/_lib/asr');

const AUDIO = Buffer.alloc(4000, 1).toString('base64');
const mkRes = () => {
  const r = { code: 0, body: null, headers: {} };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.status = (c) => { r.code = c; return r; };
  r.json = (b) => { r.body = b; return r; };
  r.end = () => r;
  return r;
};
const req = (body, extra = {}) => ({ method: 'POST', headers: {}, body, ...extra });
const ok = (text) => async () => ({ status: 200, json: async () => ({ candidates: [{ content: { parts: [{ text }] } }] }) });
const st = (s) => async () => ({ status: s, json: async () => ({}) });

test('returns text and never leaks the key', async () => {
  const seen = [];
  const h = makeHandler({ env: { GEMINI_API_KEY: 'SECRET-KEY' }, fetchImpl: async (u, o) => { seen.push([u, o]); return ok('kal meeting hai')(); } });
  const r = mkRes();
  await h(req({ audio: AUDIO, vocab: ['Voino'] }), r);
  assert.equal(r.code, 200);
  assert.deepEqual(r.body, { text: 'kal meeting hai' });
  assert.ok(!JSON.stringify(r.body).includes('SECRET'));
  assert.ok(!seen[0][0].includes('SECRET'));
  assert.equal(seen[0][1].headers['x-goog-api-key'], 'SECRET-KEY');
  assert.ok(seen[0][1].body.includes('Voino'));
});
test('quota errors map to 429 so the app can fall back', async () => {
  const h = makeHandler({ env: { GEMINI_API_KEY: 'k' }, fetchImpl: st(429) });
  const r = mkRes();
  await h(req({ audio: AUDIO }), r);
  assert.equal(r.code, 429);
  assert.equal(r.body.error, 'quota_exhausted');
});
test('upstream failure maps to 503, network error too', async () => {
  for (const f of [st(500), async () => { throw new Error('boom'); }]) {
    const r = mkRes();
    await makeHandler({ env: { GEMINI_API_KEY: 'k' }, fetchImpl: f })(req({ audio: AUDIO }), r);
    assert.equal(r.code, 503);
  }
});
test('not configured, bad method, bad audio', async () => {
  let r = mkRes();
  await makeHandler({ env: {} })(req({ audio: AUDIO }), r);
  assert.equal(r.code, 503);
  r = mkRes();
  await makeHandler({ env: { GEMINI_API_KEY: 'k' } })({ method: 'GET', headers: {} }, r);
  assert.equal(r.code, 405);
  r = mkRes();
  await makeHandler({ env: { GEMINI_API_KEY: 'k' } })(req({ audio: 'not base64!!' }), r);
  assert.equal(r.code, 400);
});
test('local rate limit', async () => {
  const h = makeHandler({ env: { GEMINI_API_KEY: 'k' }, fetchImpl: ok('x'), limiter: () => ({ ok: false, retryAfter: 9 }) });
  const r = mkRes();
  await h(req({ audio: AUDIO }), r);
  assert.equal(r.code, 429);
  assert.equal(r.headers['Retry-After'], '9');
});
