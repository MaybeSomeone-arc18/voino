// Recovery wiring integration test - runs the REAL start()/stop() path of web/whisper.js in Node
// with fake inference (dev seam __voinoTestAsr) and stubbed media devices. Verifies the session id
// carried by recovery payloads across normal captures, rejected starts, and engine-dead re-init,
// and writes the real payload + streamed transcript as a fixture for the Dart-side handler test.
// Run: node tools/recovery_wiring_test.js
'use strict';
const fs = require('fs');
const path = require('path');

let simNow = 0;
Object.defineProperty(globalThis, 'performance', { value: { now: () => simNow }, configurable: true, writable: true });
global.window = {};
global.localStorage = { getItem: () => null, setItem: () => {} };
global.location = { search: '' };

// Media stubs so `supported` is true and the real start() runs end to end.
let micRejects = false;
const fakeStream = { getTracks: () => [{ stop: () => {} }] };
Object.defineProperty(globalThis, 'navigator', { value: { mediaDevices: { getUserMedia: async () => { if (micRejects) { const e = new Error('denied'); e.name = 'NotAllowedError'; throw e; } return fakeStream; } } }, configurable: true });
global.AudioWorkletNode = class { constructor() { this.port = {}; } connect() {} disconnect() {} };
class FakeAudioContext {
  constructor() { this.audioWorklet = { addModule: async () => {} }; this.destination = {}; }
  createMediaStreamSource() { return { connect: () => {}, disconnect: () => {} }; }
  async close() {}
}
window.AudioContext = FakeAudioContext;

eval(fs.readFileSync(path.join(__dirname, '..', 'web', 'whisper.js'), 'utf8'));
const W = window.voinoWhisper;
const T = window.voinoSegTest;

const FRAME = 2048, RATE = 16000;
function makeFrame(id, speech) {
  const d = new Float32Array(FRAME);
  if (speech) d.fill(0.5);
  d[1] = id * 1e-4;
  return d;
}
let nextId = 1;
function push(n, speech) {
  for (let i = 0; i < n; i++) { T.pushFrame(makeFrame(nextId++, speech)); simNow += 128; }
}

let failures = 0;
function check(name, cond, detail) {
  console.log((cond ? 'PASS' : 'FAIL') + ' ' + name + (detail ? '  ' + detail : ''));
  if (!cond) failures++;
}

function newRecorder() {
  const r = { texts: [], errs: [], payloads: [] };
  r.cb = {
    onText: (t) => r.texts.push(t),
    onError: (m) => r.errs.push(m),
    onPartial: () => {},
    onStats: () => {},
    onRecover: (j) => r.payloads.push(JSON.parse(j)),
  };
  return r;
}

(async () => {
  // W1: normal recovery through the real start/stop wiring, first capture of the page.
  window.__voinoTestAsr = async (samples) => { // slow fake: backlog overflows into the spool
    await new Promise((res) => setTimeout(res, 1500));
    return { text: 'words from ' + samples.length + ' samples' };
  };
  let r = newRecorder();
  await W.start(r.cb.onText, () => {}, r.cb.onError, r.cb.onPartial, r.cb.onStats, r.cb.onRecover);
  push(400, true); // 51.2s of continuous speech, arrives instantly: decode falls behind
  const t0 = Date.now();
  while (Date.now() - t0 < 15000 && !r.texts.some((t) => /\[gap /.test(t))) await new Promise((res) => setTimeout(res, 100));
  await T.stop();
  check('W1 gap markers streamed during capture', r.texts.some((t) => /\[gap /.test(t)), '');
  check('W2 exactly one recovery payload, sid 1', r.payloads.length === 1 && r.payloads[0].sid === 1, r.payloads.length + ' payloads, sid ' + (r.payloads[0] && r.payloads[0].sid));
  check('W3 payload carries ops with totals', r.payloads.length > 0 && r.payloads[0].ops.length > 0 && r.payloads[0].ops.every((o) => o.str && typeof o.nth === 'number' && typeof o.total === 'number' && o.repl), '');
  fs.mkdirSync(path.join(__dirname, 'fixtures'), { recursive: true });
  fs.writeFileSync(path.join(__dirname, 'fixtures', 'recovery_payload.json'), JSON.stringify({ transcript: r.texts.join(' '), payload: JSON.stringify(r.payloads[0]) }, null, 2));

  // W4: a second capture gets the next sid (fresh start after a clean stop).
  r = newRecorder();
  await W.start(r.cb.onText, () => {}, r.cb.onError, r.cb.onPartial, r.cb.onStats, r.cb.onRecover);
  push(400, true);
  const t1 = Date.now();
  while (Date.now() - t1 < 15000 && !r.texts.some((t) => /\[gap /.test(t))) await new Promise((res) => setTimeout(res, 100));
  await T.stop();
  check('W4 second capture payload has sid 2', r.payloads.length === 1 && r.payloads[0].sid === 2, 'sid ' + (r.payloads[0] && r.payloads[0].sid));

  // W5: a rejected start (mic denied) still consumes a sid on both counters - they cannot drift
  // into accepting an older payload, because sids only ever move forward.
  r = newRecorder();
  micRejects = true;
  let threw = false;
  try { await W.start(r.cb.onText, () => {}, r.cb.onError, r.cb.onPartial, r.cb.onStats, r.cb.onRecover); } catch (e) { threw = true; }
  micRejects = false;
  check('W5 rejected start threw (mic denied)', threw, '');
  r = newRecorder();
  await W.start(r.cb.onText, () => {}, r.cb.onError, r.cb.onPartial, r.cb.onStats, r.cb.onRecover);
  push(400, true);
  const t2 = Date.now();
  while (Date.now() - t2 < 15000 && !r.texts.some((t) => /\[gap /.test(t))) await new Promise((res) => setTimeout(res, 100));
  await T.stop();
  check('W6 sid advanced past the rejected attempt (sid 4, not 3)', r.payloads.length === 1 && r.payloads[0].sid === 4, 'sid ' + (r.payloads[0] && r.payloads[0].sid));

  // W7: engine-dead re-init is refused on this page; the refusal itself consumes a sid, so a
  // payload from before the dead engine stays stale after the attempt.
  window.__voinoTestAsr = new Promise(() => {}); // load never resolves
  window.voinoInitStallMs = 50; // shrink the stall watchdog for the test
  r = newRecorder();
  let errSeen = false;
  try { await W.start(r.cb.onText, () => {}, (m) => { errSeen = true; r.cb.onError(m); }, r.cb.onPartial, r.cb.onStats, r.cb.onRecover); } catch (e) { errSeen = true; }
  check('W7 stalled init surfaced', errSeen, '');
  check('W8 engine marked dead after stalled init', T.state().engineDead === true, '');
  r = newRecorder();
  let deadMsg = '';
  await W.start(r.cb.onText, () => {}, (m) => { deadMsg = m; }, r.cb.onPartial, r.cb.onStats, r.cb.onRecover);
  check('W9 engine-dead restart refused with message', /reload/.test(deadMsg), deadMsg);
  window.voinoInitStallMs = 0;

  console.log('\n' + (failures ? failures + ' FAILURES' : 'ALL PASS'));
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR', e); process.exit(2); });
