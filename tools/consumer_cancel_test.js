// Consumer-cancel regression check for the pull-driven parts loader (web/whisper.js fetchParts).
// Covers the gap flagged 2026-11-16: a full reload proves a fresh load, not consumer cancellation.
// Cases: (A) cancel while a part fetch is in flight, (B) cancel before the first read,
// (C) intact full read with manifest. Asserts a consumer cancel is QUIET - no spurious
// signalLoaderFailure, no throw out of the stream, pending reads settle - and that real
// failures still signal. Run: node tools/consumer_cancel_test.js
'use strict';
const fs = require('fs');
const path = require('path');

global.window = {};
global.localStorage = { getItem: () => null, setItem: () => {} };
global.location = { search: '' };

// Eval the real whisper.js, exposing the two internals this check drives (test-only, in-memory).
let src = fs.readFileSync(path.join(__dirname, '..', 'web', 'whisper.js'), 'utf8');
src += '\nwindow.__fetchParts = fetchParts; window.__sigSpy = (fn) => { signalLoaderFailure = fn; };\n';
eval(src);

const fetchParts = window.__fetchParts;
let sigCalls = [];
window.__sigSpy((msg) => { sigCalls.push(msg); });

let pass = 0, fail = 0;
function check(name, cond, detail) {
  if (cond) { pass++; console.log('PASS', name); }
  else { fail++; console.log('FAIL', name, '-', detail); }
}
const PART = new Uint8Array([1, 2, 3, 4]);
function okResp(body) { return { ok: true, arrayBuffer: async () => body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength) }; }

process.on('unhandledRejection', (e) => { fail++; console.log('FAIL unhandled rejection:', String(e).slice(0, 120)); });

(async () => {
  // --- Case A: consumer cancels while part2 fetch is in flight ---
  {
    sigCalls = [];
    let releasePart2; const part2Gate = new Promise((r) => { releasePart2 = r; });
    const fetches = [];
    global.fetch = (url) => {
      fetches.push(url);
      if (url.endsWith('.part1')) return Promise.resolve(okResp(PART));
      return part2Gate.then(() => Promise.resolve(okResp(PART))); // part2 held until we say so
    };
    const s = fetchParts('http://x/', 'vaani', 'decoder_model_merged.onnx', null);
    const reader = s.getReader();
    const r1 = await reader.read(); // part1 delivered
    check('A part1 delivered', r1.done === false && r1.value.byteLength === 4, JSON.stringify(r1));
    const r2p = reader.read(); // pull for part2 starts, fetch in flight
    await new Promise((r) => setTimeout(r, 10)); // let the pull reach the fetch
    await reader.cancel('consumer-cancel'); // consumer cancels mid-fetch
    releasePart2(); // in-flight part fetch completes AFTER the cancel
    const r2 = await r2p;
    await new Promise((r) => setTimeout(r, 20)); // let any late pull continuation run
    check('A pending read settles done after cancel', r2.done === true, JSON.stringify(r2));
    check('A no loader-failure signal on consumer cancel', sigCalls.length === 0, sigCalls.join(' | '));
  }

  // --- Case B: cancel before the first read ---
  {
    sigCalls = [];
    let fetchCount = 0;
    global.fetch = () => { fetchCount++; return Promise.resolve(okResp(PART)); };
    const s = fetchParts('http://x/', 'vaani', 'decoder_model_merged.onnx', null);
    await s.cancel('consumer-cancel');
    await new Promise((r) => setTimeout(r, 20));
    check('B no fetch after immediate cancel', fetchCount === 0, 'fetches=' + fetchCount);
    check('B no loader-failure signal on immediate cancel', sigCalls.length === 0, sigCalls.join(' | '));
  }

  // --- Case C: intact path unchanged - manifest-driven full read closes cleanly ---
  {
    sigCalls = [];
    global.fetch = (url) => Promise.resolve(okResp(PART));
    const man = { parts: 2, bytes: 8 };
    const s = fetchParts('http://x/', 'vaani', 'decoder_model_merged.onnx', man);
    const reader = s.getReader();
    let got = 0, done = false;
    while (!done) { const r = await reader.read(); done = r.done; if (!done) got += r.value.byteLength; }
    check('C full read closes with all bytes', got === 8 && done === true, 'got=' + got);
    check('C no loader-failure signal on intact path', sigCalls.length === 0, sigCalls.join(' | '));
  }

  // --- Case D: real network failure mid-stream still signals (guard not swallowed) ---
  {
    sigCalls = [];
    global.fetch = (url) => url.endsWith('.part1') ? Promise.resolve(okResp(PART)) : Promise.reject(new Error('net down'));
    const s = fetchParts('http://x/', 'vaani', 'decoder_model_merged.onnx', null);
    const reader = s.getReader();
    await reader.read();
    try { await reader.read(); } catch (e) { /* stream errored as designed */ }
    await new Promise((r) => setTimeout(r, 10));
    check('D real failure still signals loader failure', sigCalls.length === 1 && /interrupted/.test(sigCalls[0]), sigCalls.join(' | '));
  }

  console.log(fail === 0 ? 'ALL PASS' : fail + ' FAILURES', '- consumer cancel path');
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.log('HARNESS ERROR', e); process.exit(2); });
