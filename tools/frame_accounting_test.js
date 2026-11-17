// Frame-accounting regression for web/whisper.js - runs in Node with a fake, delayed inference.
// Isolates loss / duplication / order / stop-drain behavior from model quality: frames carry
// identity markers, the fake ASR records exactly which frames each decode received.
// Run: node tools/frame_accounting_test.js
'use strict';
const fs = require('fs');
const path = require('path');

let simNow = 0; // simulated capture clock (ms); advanced 128 per 2048-sample frame
Object.defineProperty(globalThis, 'performance', { value: { now: () => simNow }, configurable: true, writable: true });
global.window = {};
global.localStorage = { getItem: () => null, setItem: () => {} };
global.location = { search: '' };
eval(fs.readFileSync(path.join(__dirname, '..', 'web', 'whisper.js'), 'utf8'));
const T = window.voinoSegTest;

const FRAME = 2048, RATE = 16000, FPS = RATE / FRAME; // 7.8125 fps
function makeFrame(id, speech) {
  const d = new Float32Array(FRAME);
  if (speech) d.fill(0.5);
  d[1] = id * 1e-4; // identity marker, rms impact negligible
  return d;
}
let nextId = 1;
function push(n, speech) {
  const ids = [];
  for (let i = 0; i < n; i++) { const id = nextId++; T.pushFrame(makeFrame(id, speech)); simNow += 128; ids.push(id); }
  return ids;
}
function fakeAsr(delayMs, calls) {
  return async (samples) => {
    const ids = [];
    for (let off = 1; off + 1 < samples.length + 1 && off < samples.length; off += FRAME) ids.push(Math.round(samples[off] / 1e-4));
    const rec = { ids, at: Date.now() };
    calls.push(rec);
    await new Promise((r) => setTimeout(r, delayMs));
    return { text: 'block ' + ids[0] + ' to ' + ids[ids.length - 1] };
  };
}
function flakyAsr(delayMs, calls, failFromCall) { // like fakeAsr, but every call from failFromCall on throws
  let n = 0;
  return async (samples) => {
    const ids = [];
    for (let off = 1; off + 1 < samples.length + 1 && off < samples.length; off += FRAME) ids.push(Math.round(samples[off] / 1e-4));
    calls.push({ ids });
    n++;
    await new Promise((r) => setTimeout(r, delayMs));
    if (n >= failFromCall) { calls[calls.length - 1].ok = false; throw new Error('boom'); }
    return { text: 'block ' + ids[0] + ' to ' + ids[ids.length - 1] };
  };
}
const FRAME_S = FRAME / RATE;
function gapAccounting() {
  // Exact-gap invariant: every frame never decoded must lie fully inside a marked gap interval;
  // every decoded frame must lie outside all of them. Gap edges align to frame boundaries.
  const gaps = T.gapHistory();
  const eps = 0.01;
  const inGap = (id) => gaps.some((g) => (id - 1) * FRAME_S >= g.a - eps && id * FRAME_S <= g.b + eps);
  const overlapsGap = (id) => gaps.some((g) => id * FRAME_S > g.a + FRAME_S / 2 && (id - 1) * FRAME_S < g.b - FRAME_S / 2);
  return { gaps, inGap, overlapsGap };
}
let texts = [], errs = [], recovs = [];
const cb = { onText: (t) => texts.push(t), onError: (m) => errs.push(m), onPartial: () => {}, onStats: () => {}, onRecover: (j) => { try { const d = JSON.parse(j); for (const op of d.ops) recovs.push(op); } catch (e) { errs.push('bad recover payload: ' + e.message); } } };
let failures = 0;
function check(name, cond, detail) {
  console.log((cond ? 'PASS' : 'FAIL') + ' ' + name + (detail ? '  ' + detail : ''));
  if (!cond) failures++;
}
function finalCalls(calls) { return calls; } // every fake call in these tests is final or partial; tagged by caller
function coverage(calls) {
  // returns {dupes, covered:Set} over frame ids received by SUCCESSFUL decodes
  const seen = new Set(); const dupes = [];
  for (const c of calls) { if (c.ok === false) continue; for (const id of c.ids) { if (seen.has(id)) dupes.push(id); seen.add(id); } }
  return { dupes, covered: seen };
}

async function scenarioA() {
  console.log('\nA: pause hidden inside a busy decode');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = [];
  const calls = [];
  const asr = fakeAsr(2000, calls);
  const clip1 = push(40, true);   // 5.1s speech
  push(4, false);                 // 0.5s silence -> pause commit AT ARRIVAL
  const p1 = T.tick(asr, cb);     // starts final decode of clip1 (busy 2s)
  const clip2 = push(40, true);   // second clip arrives entirely during the busy decode
  push(4, false);                 // its closing pause, also during the busy decode
  await p1;
  while (T.state().committed > 0) await T.tick(asr, cb);
  const finals = calls.slice(0, 2); // first two decodes were the two committed segments
  const f1 = new Set(finals[0].ids), f2 = new Set(finals[1].ids);
  const inter = [...f1].filter((i) => f2.has(i));
  check('A1 pause close covers clip1 speech', clip1.every((i) => f1.has(i)), '');
  check('A2 second close covers clip2 speech', clip2.every((i) => f2.has(i)), '');
  check('A3 no frame decoded twice', inter.length === 0, inter.join(','));
  check('A4 order preserved', Math.max(...finals[0].ids) < Math.min(...finals[1].ids), '');
  check('A5 finals are clip-sized (<60 frames)', finals.every((f) => f.ids.length <= 60), finals.map((f) => f.ids.length).join(','));
}

async function scenarioB() {
  console.log('\nB: 20s monologue, decode slower than speech');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = [];
  const calls = [];
  const asr = fakeAsr(1200, calls);
  const speech = push(160, true); // 20.5s continuous
  while (T.state().committed > 0 || T.state().inSeg) {
    await T.tick(asr, cb);
    if (T.state().committed === 0) break; // remaining open segment handled by stop in C; here stop explicitly
  }
  while (T.state().seg > 0) T.commitOpen('stop');
  while (T.state().committed > 0) await T.tick(asr, cb);
  const { dupes, covered } = coverage(calls);
  const missing = speech.filter((i) => !covered.has(i));
  const sizes = calls.map((c) => c.ids.length);
  check('B1 no duplication', dupes.length === 0, dupes.join(','));
  check('B2 no loss', missing.length === 0, missing.join(','));
  check('B3 bounded segments (<=70 frames)', sizes.every((s) => s <= 70), sizes.join(','));
  check('B4 order preserved', calls.every((c, i) => i === 0 || Math.min(...c.ids) > Math.min(...calls[i - 1].ids)), '');
}

async function scenarioC() {
  console.log('\nC: stop mid-speech with backlog drains bounded, lossless');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = [];
  const calls = [];
  const asr = fakeAsr(1000, calls);
  const speech = push(80, true);  // 10.2s speech, decode 1s -> some backlog
  const p1 = T.tick(asr, cb);     // busy decode of first committed chunk
  push(20, true);                 // more speech during busy decode
  window.__voinoCb = { asr, cb };
  await p1;
  await T.stop();                 // mid-utterance stop: must drain everything pending
  const { dupes, covered } = coverage(calls);
  const all = speech.concat();
  const pushed = [...Array(nextId - 1).keys()].map((i) => i + 1);
  const missing = pushed.filter((i) => !covered.has(i));
  check('C1 stop drained every pushed speech frame', pushed.filter((i) => !covered.has(i)).length === 0, missing.join(','));
  check('C2 no duplication at stop', dupes.length === 0, dupes.join(','));
  check('C3 drained in bounded segments', calls.every((c) => c.ids.length <= 70), calls.map((c) => c.ids.length).join(','));
  check('C4 order preserved through stop drain', calls.every((c, i) => i === 0 || Math.min(...c.ids) > Math.min(...calls[i - 1].ids)), '');
}

async function scenarioD() {
  console.log('\nD: extreme slowness -> backlog overflow spooled, recovered on stop');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = []; recovs = [];
  const calls = [];
  const asr = fakeAsr(6000, calls);
  push(320, true); // 41s of speech while a 6s decode crawls: backlog cap must set aside committed segments
  const p1 = T.tick(asr, cb);
  push(40, true);
  window.__voinoCb = { asr, cb };
  await p1;
  await T.stop();
  const trace = T.trace();
  const spooled = trace.filter((e) => e.e === 'spool');
  const spoolDone = trace.filter((e) => e.e === 'spool-done');
  const gapText = texts.find((t) => /\[gap /.test(t));
  check('D1 visible gap marker emitted at capture time', !!gapText, gapText || 'none');
  check('D2 overflow set frames aside, none decoded twice', spooled.length > 0 && coverage(calls).dupes.length === 0, spooled.length + ' spooled');
  const { covered } = coverage(calls);
  const nSpool = spoolDone.length;
  const fifoCalls = calls.slice(0, calls.length - nSpool).map((c) => Math.min(...c.ids));
  const spoolCalls = calls.slice(calls.length - nSpool).map((c) => Math.min(...c.ids));
  const asc = (arr) => arr.every((m, i) => i === 0 || m > arr[i - 1]);
  check('D3 fifo drain and spool drain each decode in speech order', asc(fifoCalls) && asc(spoolCalls), fifoCalls.join(',') + ' | ' + spoolCalls.join(','));
  const pushedIds = [...Array(nextId - 1).keys()].map((i) => i + 1);
  const missing = pushedIds.filter((i) => !covered.has(i));
  const { gaps, inGap, overlapsGap } = gapAccounting();
  check('D4 every undecoded frame is inside a marked gap', missing.every(inGap), gaps.map((g) => g.a.toFixed(1) + '-' + g.b.toFixed(1)).join(' '));
  const inSpoolDone = (id) => spoolDone.some((e) => id - 1 >= e.a && id - 1 <= e.b); // frame id n has arrival seq n-1
  const coveredIds = [...covered];
  check('D5 decoded frames are outside gaps or recovered on stop', coveredIds.every((id) => !overlapsGap(id) || inSpoolDone(id)), coveredIds.filter((id) => overlapsGap(id) && !inSpoolDone(id)).join(','));
  check('D6 recovered spans rewrote their markers', spoolDone.length === spooled.length && recovs.length >= 1, spoolDone.length + '/' + spooled.length + ' recovered, ' + recovs.length + ' rewrites');
}

async function scenarioE() {
  console.log('\nE: decode error during stop drain marks the rest lost');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = [];
  const calls = [];
  const asr = flakyAsr(300, calls, 2); // first decode succeeds, everything after fails
  push(80, true); // 10.2s speech -> commits at the 8s cap, remainder open
  await T.tick(asr, cb); // succeeds, consumes first committed chunk
  window.__voinoCb = { asr, cb };
  await T.stop(); // drain hits the failure: remainder must be marked, not silently dropped
  const { dupes, covered } = coverage(calls);
  check('E1 first chunk decoded exactly once', covered.size > 0 && dupes.length === 0, 'covered ' + covered.size);
  check('E2 drain error surfaced', errs.length > 0, errs[0] || '');
  const pushedIds = [...Array(nextId - 1).keys()].map((i) => i + 1);
  const missing = pushedIds.filter((i) => !covered.has(i));
  const { gaps, inGap, overlapsGap } = gapAccounting();
  check('E3 undrained frames are gap-marked lost', missing.length > 0 && missing.every(inGap), missing.length + ' lost, gaps ' + gaps.map((g) => g.a.toFixed(1) + '-' + g.b.toFixed(1)).join(' '));
  check('E4 decoded frames are not gap-marked', [...covered].every((id) => !overlapsGap(id)), '');
  check('E5 loss is visible in the transcript', texts.some((t) => /\[gap /.test(t)), '');
}

async function scenarioF() {
  console.log('\nF: stop during an in-flight final decodes it exactly once');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = [];
  const calls = [];
  const asr = fakeAsr(1500, calls);
  push(40, true);   // 5.1s speech
  push(4, false);   // pause -> commit
  const p1 = T.tick(asr, cb); // final decode in flight
  window.__voinoCb = { asr, cb };
  await T.stop();   // stop must wait for the in-flight decode, not void + re-decode it
  await p1;
  const { dupes, covered } = coverage(calls);
  check('F1 in-flight segment decoded exactly once', calls.length === 1 && dupes.length === 0, calls.length + ' decode calls');
  check('F2 its text emitted exactly once', texts.filter((t) => !/\[gap /.test(t)).length === 1, texts.join(' // '));
  const speechIds = [...Array(40).keys()].map((i) => i + 1); // trailing silence is trimmed at pause commit by design
  check('F3 nothing lost', speechIds.filter((i) => !covered.has(i)).length === 0, '');
}

async function scenarioG() {
  console.log('\nG: stop-wait against a decode that truly times out (~30s)');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = [];
  const calls = [];
  const asr = fakeAsr(60000, calls); // never returns before the 30s watchdog
  const speech = push(40, true);
  push(4, false);
  push(20, true); // more speech stays open
  const p1 = T.tick(asr, cb); // in-flight final that will hit the watchdog
  window.__voinoCb = { asr, cb };
  const t0 = Date.now();
  await T.stop(); // must wait out the watchdog, then mark everything lost - not hang, not re-decode
  await p1;
  const waitedS = (Date.now() - t0) / 1000;
  check('G1 stop resolved after the watchdog, bounded', waitedS > 25 && waitedS < 45, waitedS.toFixed(1) + 's');
  check('G2 engine marked dead, error surfaced', T.state().engineDead === true && errs.some((e) => /stopped responding/.test(e)), errs[0] || '');
  check('G3 no re-decode after the timeout', calls.length === 1, calls.length + ' decode calls');
  const pushedIds = [...Array(40).keys()].map((i) => i + 1).concat([...Array(20).keys()].map((i) => i + 45)); // speech frames only; trailing pause silence is trimmed by design
  const { gaps, inGap } = gapAccounting();
  check('G4 all speech frames gap-marked lost', pushedIds.every(inGap), gaps.map((g) => g.a.toFixed(1) + '-' + g.b.toFixed(1)).join(' '));
  check('G5 loss visible in the transcript', texts.some((t) => /\[gap /.test(t)), '');
}

async function scenarioH() {
  console.log('\nH: stop-wait against an in-flight decode that errors');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = [];
  const calls = [];
  const asr = flakyAsr(300, calls, 1); // every decode fails
  push(40, true);
  push(4, false);
  const p1 = T.tick(asr, cb); // in-flight final that will error before stop proceeds
  window.__voinoCb = { asr, cb };
  await T.stop(); // waits out the error, drain retries once, no progress -> notice + marked lost
  await p1;
  check('H1 errors surfaced', errs.length >= 1 && errs.every((e) => /Could not transcribe/.test(e)), errs.length + ' errors');
  check('H2 no infinite retry: exactly one drain re-attempt', calls.length === 2, calls.length + ' decode calls');
  const speechIds = [...Array(40).keys()].map((i) => i + 1);
  const { gaps, inGap } = gapAccounting();
  check('H3 failed speech gap-marked lost', speechIds.every(inGap), gaps.map((g) => g.a.toFixed(1) + '-' + g.b.toFixed(1)).join(' '));
  check('H4 loss visible in the transcript', texts.some((t) => /\[gap /.test(t)), '');
}

function applyGapRecovs(transcript, ops) { // mirrors logic.dart applyGapRecoveries (grouped, fail-safe)
  const byStr = new Map();
  for (const op of ops) { if (!byStr.has(op.str)) byStr.set(op.str, []); byStr.get(op.str).push(op); }
  const edits = new Map(); // position -> {len, repl}
  for (const [str, group] of byStr) {
    const positions = [];
    let i = -1;
    while ((i = transcript.indexOf(str, i + 1)) >= 0) positions.push(i);
    if (positions.length !== group[0].total) continue; // user touched these markers: leave their text alone
    for (const op of group) {
      if (op.nth < 0 || op.nth >= positions.length) continue;
      edits.set(positions[op.nth], { len: str.length, repl: op.repl });
    }
  }
  if (!edits.size) return transcript;
  const sorted = [...edits.keys()].sort((a, b) => a - b);
  let out = '', cursor = 0;
  for (const pos of sorted) {
    if (pos < cursor) continue;
    out += transcript.slice(cursor, pos);
    const e = edits.get(pos);
    out += e.repl;
    cursor = pos + e.len;
  }
  return out + transcript.slice(cursor);
}
function applyRecovs() { // simulate the Dart transcript: streamed text, then marker rewrites
  return applyGapRecovs(texts.join(' '), recovs);
}

async function scenarioI() {
  console.log('\nI: backlog overflow is spooled and recovered on stop');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = []; recovs = [];
  const calls = [];
  const asr = fakeAsr(1500, calls); // slow decode; frames arrive faster than it can finish
  const speech = push(400, true);   // 51.2s continuous: far beyond the 30s backlog cap
  window.__voinoCb = { asr, cb };
  await T.stop();                   // stop-drain decodes the open segment, then the spool
  const trace = T.trace();
  const spooled = trace.filter((e) => e.e === 'spool');
  const spoolDone = trace.filter((e) => e.e === 'spool-done');
  check('I1 overflow segments spooled, not discarded', spooled.length >= 3, spooled.length + ' spooled');
  check('I2 gap markers emitted during capture', texts.some((t) => /\[gap /.test(t)), '');
  check('I3 spool drained on stop', spoolDone.length === spooled.length, spoolDone.length + '/' + spooled.length);
  check('I4 marker rewrite emitted', recovs.length >= 1, recovs.length + ' rewrites');
  const { dupes, covered } = coverage(calls);
  const missing = speech.filter((i) => !covered.has(i));
  check('I5 no frame decoded twice', dupes.length === 0, dupes.join(','));
  check('I6 no speech frame lost', missing.length === 0, missing.join(','));
  const final = applyRecovs();
  check('I7 all gaps rewritten after full recovery', !/\[gap /.test(final), '');
  check('I8 recovered text landed in transcript', spoolDone.length > 0 && final.includes('block '), '');
}

async function scenarioJ() {
  console.log('\nJ: spool cap overflow still drops with exact gap markers');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = []; recovs = [];
  const calls = [];
  const asr = fakeAsr(1500, calls);
  const speech = push(1450, true);  // 185.6s: overflow exceeds the 120s spool cap
  window.__voinoCb = { asr, cb };
  await T.stop();
  const trace = T.trace();
  const spooled = trace.filter((e) => e.e === 'spool');
  const spoolDone = trace.filter((e) => e.e === 'spool-done');
  const spooledFrames = spooled.reduce((a, e) => a + (e.b - e.a + 1), 0);
  check('J1 spool bounded at the cap (<= 121s of frames)', spooledFrames <= 121 * (RATE / FRAME), spooledFrames + ' frames');
  check('J2 spool drained on stop', spoolDone.length === spooled.length, spoolDone.length + '/' + spooled.length);
  const { dupes, covered } = coverage(calls);
  const missing = speech.filter((i) => !covered.has(i));
  check('J3 no frame decoded twice', dupes.length === 0, dupes.slice(0, 5).join(','));
  check('J4 audio beyond the cap is lost', missing.length > 0, missing.length + ' frames lost');
  const { gaps, inGap, overlapsGap } = gapAccounting();
  check('J5 every lost frame is gap-marked', missing.every(inGap), '');
  const inSpoolDone = (id) => spoolDone.some((e) => id - 1 >= e.a && id - 1 <= e.b); // frame id n has arrival seq n-1
  check('J6 decoded-but-marked frames are exactly the recovered ones', speech.filter((i) => covered.has(i) && overlapsGap(i)).every(inSpoolDone), '');
  const final = applyRecovs();
  check('J7 unrecovered loss stays marked', /\[gap /.test(final), '');
  check('J8 recovered text landed in transcript', final.includes('block '), '');
}

function scenarioK() {
  console.log('\nK: grouped marker rewrites are fail-safe');
  const m = '[gap 0:00-0:02 not transcribed]';
  check('K1 several identical markers each rewrite', applyGapRecovs('a ' + m + ' b ' + m + ' c', [
    { str: m, nth: 0, total: 2, repl: 'X' }, { str: m, nth: 1, total: 2, repl: 'Y' },
  ]) === 'a X b Y c', '');
  check('K2 replacement containing its own marker string works', applyGapRecovs('a ' + m + ' c', [
    { str: m, nth: 0, total: 1, repl: 'X ' + m + ' Y' },
  ]) === 'a X ' + m + ' Y c', '');
  check('K3 edited marker count fails safe (duplicated marker)', applyGapRecovs('a ' + m + ' b ' + m + ' c ' + m, [
    { str: m, nth: 0, total: 2, repl: 'X' }, { str: m, nth: 1, total: 2, repl: 'Y' },
  ]) === 'a ' + m + ' b ' + m + ' c ' + m, '');
  check('K4 deleted marker fails safe (fewer copies than total)', applyGapRecovs('a ' + m + ' c', [
    { str: m, nth: 0, total: 2, repl: 'X' }, { str: m, nth: 1, total: 2, repl: 'Y' },
  ]) === 'a ' + m + ' c', '');
  check('K5 different marker strings rewrite independently', applyGapRecovs('a ' + m + ' b [gap 0:02-0:04 not transcribed] c', [
    { str: m, nth: 0, total: 1, repl: 'X' }, { str: '[gap 0:02-0:04 not transcribed]', nth: 0, total: 1, repl: 'Y' },
  ]) === 'a X b Y c', '');
}

async function scenarioL() {
  console.log('\nL: engine dies (watchdog) during the spool drain');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = []; recovs = [];
  const calls = [];
  let drainPhase = false; // set when the spool drain notice fires, so the next decode hangs
  const origWarn = console.warn;
  console.warn = (...a) => { if (a.join(' ').includes('set aside')) drainPhase = true; origWarn(...a); };
  const asr = async (samples) => { // fast for fifo decodes, hangs once the spool drain begins
    const ids = [];
    for (let off = 1; off + 1 < samples.length + 1 && off < samples.length; off += FRAME) ids.push(Math.round(samples[off] / 1e-4));
    calls.push({ ids, spool: drainPhase });
    await new Promise((r) => setTimeout(r, drainPhase ? 60000 : 1500));
    return { text: 'block ' + ids[0] + ' to ' + ids[ids.length - 1] };
  };
  push(400, true); // 51.2s continuous: overflows the backlog into the spool
  window.__voinoCb = { asr, cb };
  const t0 = Date.now();
  await T.stop();
  console.warn = origWarn;
  const waitedS = (Date.now() - t0) / 1000;
  const trace = T.trace();
  const spooled = trace.filter((e) => e.e === 'spool');
  const spoolDone = trace.filter((e) => e.e === 'spool-done');
  const spoolCalls = calls.filter((c) => c.spool);
  check('L1 stop resolved after one watchdog, bounded', waitedS > 25 && waitedS < 45, waitedS.toFixed(1) + 's');
  check('L2 engine-dead error surfaced', T.state().engineDead === true && errs.some((e) => /stopped responding/.test(e)), '');
  check('L3 drain aborted: only the hung spool decode attempted', spoolCalls.length === 1 && spoolDone.length === 0, spoolCalls.length + ' spool calls, ' + spoolDone.length + ' done of ' + spooled.length);
  check('L4 no recovery rewrites emitted for unrecovered audio', recovs.length === 0, recovs.length + ' rewrites');
  check('L5 unrecovered loss stays marked', texts.some((t) => /\[gap /.test(t)), '');
}

async function scenarioM() {
  console.log('\nM: a second stop during the spool drain cannot double-decode');
  T.reset(); simNow = 0; nextId = 1; texts = []; errs = []; recovs = [];
  const calls = [];
  const asr = fakeAsr(1500, calls);
  push(400, true);
  window.__voinoCb = { asr, cb };
  const p1 = T.stop();
  const p2 = T.stop(); // reentrant: must wait for the first, then no-op over cleaned state
  await Promise.all([p1, p2]);
  const trace = T.trace();
  const spooled = trace.filter((e) => e.e === 'spool');
  const spoolDone = trace.filter((e) => e.e === 'spool-done');
  check('M1 spool drained exactly once across both stops', spoolDone.length === spooled.length, spoolDone.length + '/' + spooled.length);
  const { dupes } = coverage(calls);
  check('M2 no frame decoded twice', dupes.length === 0, dupes.join(','));
  check('M3 single rewrite payload', recovs.length > 0 && errs.every((e) => !/bad recover/.test(e)), recovs.length + ' rewrites');
}

const ONLY = process.env.SCN ? process.env.SCN.split(',') : null;
(async () => {
  const run = async (name, fn) => { if (!ONLY || ONLY.includes(name)) await fn(); };
  await run('A', scenarioA);
  await run('B', scenarioB);
  await run('C', scenarioC);
  await run('D', scenarioD);
  await run('E', scenarioE);
  await run('F', scenarioF);
  await run('G', scenarioG);
  await run('H', scenarioH);
  await run('I', scenarioI);
  await run('J', scenarioJ);
  await run('K', scenarioK);
  await run('L', scenarioL);
  await run('M', scenarioM);
  console.log('\n' + (failures ? failures + ' FAILURES' : 'ALL PASS'));
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR', e); process.exit(2); });
