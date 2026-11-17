// Web-only local speech-to-text: multilingual Whisper tiny in the browser via transformers.js (WASM).
// Hindi + English with per-segment language detection. Hindi output is romanized to English letters (Hinglish).
// The model (about 40 MB quantized) downloads on first use and is cached by the browser.
//
// Live mode: audio is captured continuously (no 5 s recorder chunks). Every STEP_MS the open
// segment is re-transcribed and shown as a PARTIAL result right away; when the speaker pauses
// (or the segment reaches MAX_SEG_S) the segment is transcribed once more and committed as FINAL.
const TRANSFORMERS = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/dist/transformers.min.js';
// Local engines. 'multi' is the stock multilingual tiny (MIT), lazy-loaded from huggingface.co on first use.
// The 'hinglish' variant is temporarily removed while its upstream training-data licensing is reviewed.
const VARIANTS = {
  multi: { label: 'Stock tiny (MIT)', model: 'Xenova/whisper-tiny', lang: 'hi' },
  gemini: { label: 'Gemini (cloud, free tier)', cloud: true, lang: null },
  vaani: { label: 'Vaani Hindi tiny (Apache-2.0)', model: 'vaani', local: true, lang: 'hi' },
};
let unknownSavedVariant = null; // set when saved settings name a model this build does not have
let variant = (() => {
  try {
    const v = localStorage.getItem('voinoAsr');
    if (VARIANTS[v]) return v;
    if (v) { unknownSavedVariant = v; console.warn('voino asr: saved model "' + v + '" is not in this build - using ' + VARIANTS.multi.label); }
    return 'multi';
  } catch (_) { return 'multi'; }
})();
const asrPromises = {};
const RATE = 16000;
const STEP_MS = 700; // how often a partial update is attempted (skipped while a decode is running)
const PAUSE_MS = 400; // silence that ends a segment
const MAX_SEG_S = 8; // long monologues are split at the quietest point instead of growing
const MAX_SEG_S_CLOUD = 5; // cloud decodes only on finals, so split sooner to keep text feeling live
const PRE_ROLL = 3; // frames (about 0.4 s) kept from before speech starts so first syllables survive
const MIN_SECONDS = 0.5;
const SILENCE_RMS = 0.004;
const BUFFER = 2048; // 128 ms frames at 16 kHz

const supported = !!(navigator.mediaDevices?.getUserMedia && (window.AudioContext || window.webkitAudioContext));

let TensorCls = null;
let stream = null, audioCtx = null, source = null, proc = null, timer = null;
let running = false, busy = false, busyFinal = false; // busyFinal: the in-flight decode owns committed[0]
let seg = []; // frames {d: Float32Array, rms, sp} of the open segment (speech started, not yet committed)
let pre = []; // recent frames while idle
let inSeg = false;
let committed = [];        // FIFO of FINAL frame-arrays, committed at CAPTURE time; decode order == speech order
let committedSamples = 0;
let segSamples = 0, speechSamples = 0, lastSpeechAt = 0, lastPartial = '';
let vocab = (() => { try { return JSON.parse(localStorage.getItem('voinoVocab') || '[]'); } catch (_) { return []; } })();

const HALLUCINATIONS = /^(?:thanks for watching|thank you\.?|you|bye\.?|\.+)$/i;

// Engines whose model files are not shipped with this build are treated as not installed.
// (Static hosts may answer a missing file with index.html and status 200, so check the content type too.)
const availability = {};
function isInstalled(name) {
  const v = VARIANTS[name];
  if (!v) return Promise.resolve(false);
  if (!v.local) return Promise.resolve(true); // remote model or cloud route
  availability[name] ??= (async () => {
    try {
      const base = new URL('models/', globalThis.document?.baseURI || location.href).href;
      const r = await fetch(base + v.model + '/config.json', { cache: 'no-cache', signal: AbortSignal.timeout(10000) });
      const t = r.headers.get('content-type') || '';
      if (!r.ok || t.includes('html')) return false;
      const p = await fetch(base + v.model + '/onnx/' + decoderFile(name) + '.part1', { method: 'HEAD', cache: 'no-cache', signal: AbortSignal.timeout(10000) });
      return p.ok && !(p.headers.get('content-type') || '').includes('html');
    } catch (e) {
      // A missing package fails fast (404/wrong type) above; a network or server stall must not
      // silently downgrade the engine - treat it as present and let the guarded init path decide.
      if (e && e.name === 'TimeoutError') return true;
      return false;
    }
  })();
  return availability[name];
}
let notice = '';
let onNotice = null;
function setNotice(t) { notice = t; onNotice?.(t); if (t) console.warn('voino asr:', t); }

const MAX_BUF_S = 30; // hard cap on undecoded backlog; beyond this audio is dropped and marked as a gap, not silently lost
const DECODE_TIMEOUT_MS = 30000; // a decode that never returns must not freeze capture or stop()
// A page timer can only catch a STALLED init (no progress events for this long) while the
// renderer event loop is still alive; a frozen renderer runs no timers, so this never claims
// to cover that case. Rejection cannot cancel the pending pipeline() either - the init epoch
// below quarantines its late completion instead. Compile/graph-init phases emit no progress
// events, so the window stays well above the slowest compile we have measured (~60s).
const INIT_STALL_MS = 180000;
let lastDropNotice = 0;
let decodeEpoch = 0;    // bumped whenever an in-flight decode's result must be discarded (timeout, stop, restart)
let initEpoch = 0;      // bumped to void a stale model-init completion after an init stall
let engineDead = false; // pipeline disposed after a stuck decode or stalled init; only a page reload recovers
const initActivity = {}; // variant -> last progress-event time, for the stall watchdog
let gaps = [];          // closed {a, b} intervals (meeting seconds) captured but not transcribed
let frameSeq = 0;       // dev-only: arrival counter stamped on each frame
const segTrace = [];    // dev-only: frame/commit/final events for the regression trace
const gapHistory = [];  // dev-only: every marked interval, exact seconds, for the frame-accounting regression
// Audio the backlog would otherwise discard is set aside (in memory, never on disk) and decoded
// during stop(), when the decoder has the machine to itself. The cap bounds memory at
// MAX_SPOOL_S * 16kHz * 4 bytes (120s of Float32 = 7.7MB); beyond it, audio is dropped and
// gap-marked as before. This is not unlimited recording: the gap marker is emitted either way,
// and it is rewritten only by a decode that actually succeeds.
const MAX_SPOOL_S = 120;
const spool = [];        // {a, b, frames} segments preserved on backlog overflow, in speech order
let spooledSamples = 0;
const emittedGaps = [];  // {str, a, b, nth} gap markers already in the transcript, so a recovered span rewrites exactly its own marker
function markGap(a, b) { // one exact lost interval; merge only truly contiguous losses so transcribed islands stay excluded
  a = Math.max(0, a);
  if (b - a < 0.3) return;
  const last = gaps[gaps.length - 1];
  if (last && a <= last.b + 0.2) last.b = Math.max(last.b, b);
  else gaps.push({ a, b });
  const h = gapHistory[gapHistory.length - 1];
  if (h && a <= h.b + 0.2) h.b = Math.max(h.b, b);
  else gapHistory.push({ a, b });
}
function fmtGap(s) { const t = Math.round(s); return Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0'); }
function flushGaps(cb) {
  while (gaps.length) {
    const g = gaps.shift();
    const str = '[gap ' + fmtGap(g.a) + '-' + fmtGap(g.b) + ' not transcribed]';
    let nth = 0;
    for (const e of emittedGaps) if (e.str === str) nth++;
    emittedGaps.push({ str, a: g.a, b: g.b, nth });
    cb?.onText?.(str);
  }
}
async function disposeEngines() { for (const k of Object.keys(asrPromises)) { const p = asrPromises[k]; asrPromises[k] = null; try { (await p)?.dispose?.(); } catch (_) {} } }
let engineResetPromise = null; // a stuck worker cannot be revived in place: the page reloads once the transcript is safe
// Diagnostics (dev-only, URL-gated): ?singlefile=1 loads the decoder as one assembled file
// instead of the multi-part assembly path.
const URL_PARAMS = new URLSearchParams((typeof location !== 'undefined' && location.search) || '');
const SINGLE_FILE = URL_PARAMS.get('singlefile') === '1';
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
// ?stagelog=1 beacons init stages to a local collector: local diagnostics only, never shipped.
const STAGE_LOG = URL_PARAMS.has('stagelog');
function stage(s) { if (!STAGE_LOG) return; try { navigator.sendBeacon('http://127.0.0.1:8138/save', JSON.stringify({ apppath: true, singlefile: SINGLE_FILE, stage: s, at: Date.now() })); } catch (_) {} }
// <<< VOINO TEST SEAM

// The decoder is split in parts (GitHub web uploads are capped at 25 MB per file); put it back together on load.
function decoderFile(name) { return (VARIANTS[name].dtype && VARIANTS[name].dtype.decoder_model_merged === 'fp32') ? 'decoder_model_merged.onnx' : 'decoder_model_merged_quantized.onnx'; }
// A sibling <file>.parts.json manifest ({parts, bytes, sizes, sha256}) pins the expected part sequence.
// match() preflights every part with a HEAD request before streaming and surfaces a notice on failure: a
// missing or truncated part must not pass as a normal end-of-sequence. transformers.js settles neither a
// rejected cache.match nor an errored response body (verified locally), so the notice is raised from here;
// the stall watchdog remains the backstop that ends the wait. Without a manifest (legacy packaging) the
// loader keeps the old sequential-until-missing behavior, which cannot detect gaps.
async function preflightParts(base, dir, file, man) {
  for (let i = 1; i <= man.parts; i++) {
    const r = await fetch(base + dir + '/onnx/' + file + '.part' + i, { method: 'HEAD' });
    if (!r.ok) throw new Error('model part unavailable: ' + file + '.part' + i + ' of ' + man.parts + ' (HTTP ' + r.status + ')');
    const len = Number(r.headers.get('content-length'));
    if (man.sizes && len !== man.sizes[i - 1]) throw new Error('model part size mismatch: ' + file + '.part' + i + ' is ' + len + ' bytes, expected ' + man.sizes[i - 1]);
  }
}
// transformers.js settles neither a rejected cache.match nor an errored body, so a detected loader failure
// must reject the loadModel race from out here: start() then throws and the UI leaves the downloading state.
let loaderFailureReject = null;
function signalLoaderFailure(msg) {
  setNotice(msg);
  const e = new Error(msg);
  e.loaderFailure = true;
  try { loaderFailureReject?.(e); } catch (_) {}
}
function fetchParts(base, dir, file, man) {
  let i = 0, sent = 0, done = false, cancelled = false;
  return new ReadableStream({
    async pull(ctrl) { // pull-driven: the consumer's read rate sets the fetch rate, so parts never pile up in memory
      if (done || cancelled) return;
      i++;
      try {
        if (man && i > man.parts) {
          done = true;
          if (sent !== man.bytes) {
            signalLoaderFailure('The on-device model files are incomplete or corrupt - ' + file + ' got ' + sent + ' of ' + man.bytes + ' bytes. Reload this page to download them again.');
            ctrl.error(new Error('model parts incomplete: ' + file));
            return;
          }
          ctrl.close();
          return;
        }
        const r = await fetch(base + dir + '/onnx/' + file + '.part' + i);
        if (cancelled) return; // consumer went away mid-part: quiet, not a failure
        if (!r.ok) {
          done = true;
          if (i === 1) { ctrl.error(new Error('model part missing: ' + file + '.part1')); return; }
          if (man) {
            signalLoaderFailure('The on-device model files are incomplete or corrupt - model part missing: ' + file + '.part' + i + ' of ' + man.parts + '. Reload this page to download them again.');
            ctrl.error(new Error('model part missing: ' + file + '.part' + i));
            return;
          }
          ctrl.close(); // no manifest: sequential-until-missing, unchanged legacy behavior
          return;
        }
        const b = new Uint8Array(await r.arrayBuffer());
        if (cancelled) return;
        sent += b.byteLength;
        ctrl.enqueue(b);
      } catch (e) { // network failure mid-stream: say so, then error the stream (transformers.js will not surface it)
        if (cancelled) return; // a consumer cancel during an in-flight part is not an interruption
        done = true;
        signalLoaderFailure('The on-device model download was interrupted. Reload this page to download it again.');
        ctrl.error(e);
      }
    },
    cancel() { cancelled = true; done = true; } // consumer cancelled: stop pulling, no loader-failure signal
  });
}
function hinglishCache(base) {
  return {
    async match(req) {
      const url = typeof req === 'string' ? req : req.url;
      const m = url.match(/\/(hinglish|vaani)\/onnx\/(decoder_model_merged(?:_quantized)?\.onnx)$/);
      if (!m) return undefined;
      if (SINGLE_FILE) return fetch(base + m[1] + '/onnx/' + m[2]); // one assembled file, no part assembly
      let man = null;
      try { const r = await fetch(base + m[1] + '/onnx/' + m[2] + '.parts.json'); if (r.ok) man = await r.json(); } catch (_) {}
      if (man) {
        try { await preflightParts(base, m[1], m[2], man); }
        catch (e) { signalLoaderFailure('The on-device model files are incomplete or corrupt - ' + e.message + ' Reload this page to download them again.'); throw e; }
      }
      return new Response(fetchParts(base, m[1], m[2], man), { status: 200, headers: { 'content-type': 'application/octet-stream' } });
    },
    async put() {},
  };
}

async function loadModel(onProgress, name = variant) {
  if (VARIANTS[name].cloud) return null; // nothing to download; the local engine loads only if the cloud is unavailable
  // The stall watchdog wraps the WHOLE load, install probe included: a hung probe must not
  // pend start() forever. Progress events (and each probe step) refresh initActivity.
  initActivity[name] = Date.now();
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
  stage('loadModel-entry:' + name);
// <<< VOINO TEST SEAM
  let iv = null;
  const watchdog = new Promise((_, rej) => {
    iv = setInterval(() => {
      let stall = INIT_STALL_MS;
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
      if (Number(window.voinoInitStallMs) > 0) stall = Number(window.voinoInitStallMs); // test-only watchdog shrink
// <<< VOINO TEST SEAM
      if (Date.now() - (initActivity[name] || 0) > stall) { clearInterval(iv); rej(new Error('init-timeout')); }
    }, 1000);
  });
  const loaderWatch = new Promise((_, rej) => { loaderFailureReject = rej; }); // rejects on detected dead/corrupt local weights
  try {
    return await Promise.race([loadModelInner(onProgress, name), watchdog, loaderWatch]);
  } catch (e) {
    if (e && e.loaderFailure) { // known-dead weights: fail closed like a stall, keep the precise message
      initEpoch++;
      decodeEpoch++;
      engineDead = true;
      disposeEngines(); // fire-and-forget; the pending pipeline() never settles and is voided by the epoch bump
      throw e;
    }
    if (e && e.message === 'init-timeout') {
      initEpoch++;   // void the still-pending init; it self-disposes if it ever resolves
      decodeEpoch++;
      engineDead = true; // a same-page retry could double-initialize; only a reload is safe
      disposeEngines();  // fire-and-forget: start() must not hang on disposal
      const msg = 'The on-device model did not finish loading. Reload this page and start again - the first load can take several minutes on a slow connection.';
      setNotice(msg);
      throw new Error(msg);
    }
    throw e;
  } finally {
    clearInterval(iv);
    loaderFailureReject = null;
  }
}

async function loadModelInner(onProgress, name) {
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
  if (window.__voinoTestAsr) return window.__voinoTestAsr; // test-only fake inference; the app never sets it
// <<< VOINO TEST SEAM
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
  stage('probe-start');
// <<< VOINO TEST SEAM
  if (!(await isInstalled(name))) {
    initActivity[name] = Date.now();
    const missing = VARIANTS[name].label;
    if (name === variant) setVariant('multi');
    name = 'multi';
    setNotice(`${missing} is not installed in this build; using ${VARIANTS.multi.label}.`);
  }
  const v = VARIANTS[name];
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
  stage('probe-done:' + name);
// <<< VOINO TEST SEAM
  if (!asrPromises[name]) {
    const myInitEpoch = initEpoch; // if a stall watchdog fires while this init is pending, its late completion is void
    asrPromises[name] = (async () => {
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
      stage('import-start');
// <<< VOINO TEST SEAM
      const { pipeline, env, Tensor } = await import(TRANSFORMERS);
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
      stage('import-done');
// <<< VOINO TEST SEAM
      TensorCls = Tensor;
      env.useBrowserCache = true;
      try { env.backends.onnx.wasm.proxy = true; } catch (_) {} // run inference in a worker, off the UI thread
      if (v.local) {
        const base = new URL('models/', globalThis.document?.baseURI || location.href).href;
        env.allowLocalModels = true; env.allowRemoteModels = false; env.localModelPath = base;
        env.useCustomCache = true; env.customCache = hinglishCache(base);
      } else {
        env.allowLocalModels = false; env.allowRemoteModels = true; env.useCustomCache = false;
      }
      const files = {};
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
      stage('pipeline-called');
// <<< VOINO TEST SEAM
      const pipe = await pipeline('automatic-speech-recognition', v.model, {
        dtype: v.dtype || 'q8',
        progress_callback: (p) => {
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
          if (!files.__staged) { files.__staged = 1; stage('first-progress'); }
// <<< VOINO TEST SEAM
          initActivity[name] = Date.now(); // any file activity proves the init is alive, not stalled
          if (p.status !== 'progress' || !p.total || !isFinite(p.loaded)) return;
          files[p.file] = { loaded: p.loaded, total: p.total };
          const all = Object.values(files);
          const total = all.reduce((a, f) => a + f.total, 0);
          const loaded = all.reduce((a, f) => a + f.loaded, 0);
          const pct = Math.min(99, Math.round((loaded / total) * 100));
          if (isFinite(pct)) onProgress(pct); // never emit NaN: Dart toDartInt throws and rejects start()
        },
      });
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
      stage('pipeline-resolved');
// <<< VOINO TEST SEAM
      if (myInitEpoch !== initEpoch) {
        // Stalled and already reported dead: quarantine the late completion so it is never
        // stored, never decoded on, and does not leak its worker.
        try { pipe?.dispose?.(); } catch (_) {}
        throw new Error('init-voided');
      }
      return pipe;
    })().catch((e) => {
      delete asrPromises[name]; // allow retry
      throw e;
    });
  }
  return asrPromises[name];
}

function joined(frames) {
  let n = 0;
  for (const f of frames) n += f.d.length;
  const out = new Float32Array(n);
  let o = 0;
  for (const f of frames) { out.set(f.d, o); o += f.d.length; }
  return out;
}

function resetSegment() {
  seg = []; pre = []; inSeg = false; segSamples = 0; speechSamples = 0; lastPartial = '';
}

function recount() {
  segSamples = 0; speechSamples = 0;
  for (const f of seg) { segSamples += f.d.length; if (f.sp) speechSamples += f.d.length; }
}

// Every decode is recorded here (window.voinoLog) and shown in the ASR debug panel.
const log = (window.voinoLog = []);
const capture = (window.voinoCapture = { samples: 0, t0: 0 }); // audio actually received vs wall clock (detects dropped audio)
let onLog = null;

// ---- Gemini through our own /api/transcribe route (the key stays on the server) ----
let cloudBlockedUntil = 0; // after a quota or network failure, stay on-device until this time
const CLOUD_RETRY_MS = 60000;
let curCb = null;

function wavBase64(samples) {
  const n = samples.length;
  const buf = new ArrayBuffer(44 + n * 2);
  const dv = new DataView(buf);
  const w = (o, t) => { for (let i = 0; i < t.length; i++) dv.setUint8(o + i, t.charCodeAt(i)); };
  w(0, 'RIFF'); dv.setUint32(4, 36 + n * 2, true); w(8, 'WAVE'); w(12, 'fmt ');
  dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true);
  dv.setUint32(24, RATE, true); dv.setUint32(28, RATE * 2, true); dv.setUint16(32, 2, true); dv.setUint16(34, 16, true);
  w(36, 'data'); dv.setUint32(40, n * 2, true);
  for (let i = 0; i < n; i++) dv.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 32767, true);
  const u8 = new Uint8Array(buf);
  let bin = '';
  for (let i = 0; i < u8.length; i += 8192) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 8192));
  return btoa(bin);
}

async function geminiText(samples) {
  const url = new URL('api/transcribe', globalThis.document?.baseURI || location.href).href;
  const r = await fetch(url, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ audio: wavBase64(samples), vocab }),
  });
  if (!r.ok) {
    let code = '';
    try { code = (await r.json()).error || ''; } catch (_) {}
    const e = new Error(code || 'http_' + r.status);
    e.status = r.status;
    throw e;
  }
  return ((await r.json()).text || '').trim();
}

async function decode(asr, samples, isFinal) {
  const v = VARIANTS[variant];
  const t0 = performance.now();
  let engine = variant;
  let raw = null;
  if (v.cloud) {
    if (!isFinal) return ''; // no partial calls to the cloud: they would burn the free quota
    if (Date.now() >= cloudBlockedUntil) {
      try { raw = await geminiText(samples); }
      catch (e) {
        cloudBlockedUntil = Date.now() + CLOUD_RETRY_MS;
        const quota = e.status === 429;
        const msg = quota ? 'Gemini limit reached, switched to on-device. Will retry in a minute.'
          : 'Gemini is unavailable (' + (e.message || 'error') + '), switched to on-device. Will retry in a minute.';
        setNotice(msg);
        curCb?.onError?.(msg);
      }
    }
    if (raw === null) { // on-device fallback for this segment
      engine = 'multi';
      asr = await loadModel(() => {}, 'multi');
    }
  }
  const vv = VARIANTS[engine];
  const lang = vv.lang;
  const opts = { task: 'transcribe', max_new_tokens: Math.ceil((samples.length / RATE) * 9) + 12 };
  if (lang) opts.language = lang;
  if (raw === null) raw = ((await asr(samples, opts))?.text || '').trim();
  let text = window.voinoRomanize ? window.voinoRomanize(raw) : raw;
  const AT = window.voinoAsrText;
  if (AT) { text = AT.collapseRepeats(text); text = AT.applyVocabulary(text, vocab); }
  const halluc = HALLUCINATIONS.test(text);
  let rms = 0;
  for (let i = 0; i < samples.length; i++) rms += samples[i] * samples[i];
  rms = Math.sqrt(rms / samples.length);
  const entry = {
    t: new Date().toLocaleTimeString(), engine, model: VARIANTS[engine].model, lang: lang || 'auto', final: isFinal,
    seconds: +(samples.length / RATE).toFixed(1), ms: Math.round(performance.now() - t0),
    rms: +rms.toFixed(4), raw, shown: halluc ? '' : text, dropped: halluc,
  };
  log.push(entry); if (log.length > 200) log.shift();
  onLog?.(entry);
  return halluc ? '' : text;
}

// Index of the quietest frame in the open segment, capped at MAX_SEG_S of frames: a safe place to
// cut a long monologue. The cap keeps forced splits near MAX_SEG_S even when decode-busy skips let
// the backlog grow past it (measured: 14.7s finals), bounding settle latency.
function quietestSplit() {
  const cap = Math.max(2, Math.floor((RATE * MAX_SEG_S) / BUFFER));
  const hi = Math.min(seg.length - 2, cap);
  const lo = Math.min(Math.max(2, Math.floor(seg.length / 2)), hi - 1);
  if (hi < 2 || lo >= hi) return -1;
  let best = -1, bestRms = Infinity;
  for (let i = lo; i <= hi; i++) if (seg[i].rms < bestRms) { bestRms = seg[i].rms; best = i; }
  return best;
}

// Move frames from the open segment into the committed FIFO. Called only from pushFrame and stop
// (capture time), never from decode callbacks - so a busy decode cannot change which speech lands
// in which finalized segment. Each frame is committed exactly once; tick() consumes a committed
// segment only after its decode succeeds, so speech is neither lost nor decoded twice.
function commitOpen(reason) {
  if (!seg.length) return;
  let n = seg.length;
  if (reason === 'pause') {
    let last = seg.length - 1;
    while (last > 0 && !seg[last].sp) last--;
    n = Math.min(seg.length, last + 3); // trailing silence trimmed, a breath of context kept
  } else if (segSamples > RATE * MAX_SEG_S) { // 'maxlen' / 'stop' chunk: cut at the quietest frame within the cap
    const q = quietestSplit();
    if (q > 0) n = q;
  }
  const frames = seg.slice(0, n);
  const spN = frames.reduce((a, f) => a + (f.sp ? f.d.length : 0), 0);
  seg = seg.slice(n);
  recount();
  inSeg = seg.some((f) => f.sp);
  if (!inSeg) { seg = []; segSamples = 0; speechSamples = 0; }
  const minSp = reason === 'stop' ? 1 : RATE * MIN_SECONDS; // a stop flushes even a short trailing utterance
  if (spN >= minSp) { committed.push(frames); committedSamples += frames.reduce((a, f) => a + f.d.length, 0); segTrace.push({ e: 'commit', reason, a: frames[0].seq, b: frames[frames.length - 1].seq }); }
}

// Frame accounting happens HERE, per arriving frame: pauses and over-length segments are committed
// the moment they are observed (decode-busy or not), and the backlog cap drops whole committed
// segments - the oldest audio - with a visible gap, never arbitrary mid-segment frames.
function pushFrame(data) {
  if (!running) return;
  let sum = 0;
  for (let i = 0; i < data.length; i++) sum += data[i] * data[i];
  const rms = Math.sqrt(sum / data.length);
  const sp = rms >= SILENCE_RMS;
  const fr = { d: data, rms, sp, seq: frameSeq++ }; // seq: dev-only arrival order for the regression trace
  if (sp) lastSpeechAt = performance.now();
  if (!inSeg) {
    if (sp) { inSeg = true; seg = pre.concat([fr]); pre = []; recount(); }
    else { pre.push(fr); if (pre.length > PRE_ROLL) pre.shift(); }
  } else {
    seg.push(fr); segSamples += data.length; if (sp) speechSamples += data.length;
    if (!sp && performance.now() - lastSpeechAt > PAUSE_MS) commitOpen('pause');
    else if (segSamples > RATE * (VARIANTS[variant].cloud ? MAX_SEG_S_CLOUD : MAX_SEG_S)) commitOpen('maxlen');
    const pending = committedSamples + segSamples;
    if (pending > RATE * MAX_BUF_S) { // decode is falling behind: drop the oldest committed audio, but say so visibly
      const idx = (busyFinal && committed.length) ? 1 : 0; // committed[0] is being decoded right now: never drop it under it
      while (committed.length > idx && committedSamples + segSamples > RATE * MAX_BUF_S) {
        const c = committed.splice(idx, 1)[0];
        const n = c.reduce((a, f) => a + f.d.length, 0);
        committedSamples -= n;
        const ga = (c[0].seq * BUFFER) / RATE, gb = ((c[c.length - 1].seq + 1) * BUFFER) / RATE;
        if (spooledSamples + n <= RATE * MAX_SPOOL_S) { // preserve the only copy (bounded); marker still emitted now
          spool.push({ a: ga, b: gb, frames: c });
          spooledSamples += n;
          segTrace.push({ e: 'spool', a: c[0].seq, b: c[c.length - 1].seq });
        }
        markGap(ga, gb); // exact span of this dropped segment, no more
      }
      if (performance.now() - lastDropNotice > 10000) {
        lastDropNotice = performance.now();
        setNotice('Listening is overloaded - some audio was skipped.');
      }
    }
  }
  capture.samples += data.length;
  if (capture.keep) capture.keep.push(data);
}

async function tick(asr, cb) {
  if (busy || engineDead) return;
  // Finals come only from the committed FIFO (speech order). Partials preview the open segment
  // and never consume anything.
  let frames, isFinal;
  if (committed.length) { frames = committed[0]; isFinal = true; segTrace.push({ e: 'final-start', a: frames[0].seq, b: frames[frames.length - 1].seq }); }
  else {
    if (!inSeg) return;
    if (speechSamples < RATE * MIN_SECONDS) {
      if (performance.now() - lastSpeechAt > 1500) resetSegment(); // a click or cough, not speech
      return;
    }
    if (!speechSamples) { resetSegment(); return; }
    frames = seg; isFinal = false;
  }
  const myEpoch = decodeEpoch;
  busy = true; busyFinal = isFinal;
  try {
    const t0 = performance.now();
    // A decode that never returns must not freeze capture or stop(): race it against a watchdog.
    // The WASM inference itself cannot be cancelled, so the watchdog only DETACHES: the epoch
    // bump voids the late result and the worker is disposed, so nothing decodes concurrently on it.
    let watchdog;
    const text = await Promise.race([
      decode(asr, joined(frames), isFinal),
      new Promise((_, rej) => { watchdog = setTimeout(() => rej(new Error('decode-timeout')), DECODE_TIMEOUT_MS); }),
    ]).finally(() => clearTimeout(watchdog));
    if (myEpoch !== decodeEpoch) { if (isFinal) segTrace.push({ e: 'final-void', a: frames[0].seq, b: frames[frames.length - 1].seq }); return; } // a newer epoch owns the capture now; this result is void
    const ms = Math.round(performance.now() - t0);
    cb.onStats?.(ms, frames.reduce((a, f) => a + f.d.length, 0) / RATE, isFinal);
    if (isFinal) {
      // Consumed only on success: order preserved, nothing decoded twice, nothing skipped.
      committed.shift();
      segTrace.push({ e: 'final-done', a: frames[0].seq, b: frames[frames.length - 1].seq });
      committedSamples -= frames.reduce((a, f) => a + f.d.length, 0);
      lastPartial = '';
      cb.onPartial?.('');
      flushGaps(cb); // surface any skipped intervals before new text
      if (text) cb.onText(text);
    } else if (text && text !== lastPartial) {
      lastPartial = text;
      cb.onPartial?.(text);
    }
  } catch (e) {
    if (e?.message === 'decode-timeout') {
      decodeEpoch++;    // the stuck decode's late result is void
      engineDead = true;
      // Frames keep arriving and are gap-marked exactly: by backlog overflow while listening,
      // and by the undrained-remainder marking in stop().
      // The WASM inference cannot be cancelled and a disposed worker cannot be re-entered
      // (restarting after dispose fails), so the only recovery is a page reload after the
      // transcript is safely persisted. Disposal is fire-and-forget: stop() must not hang on it.
      disposeEngines();
      setNotice('Transcription engine is unresponsive. Stop listening - your notes so far are kept - then reload this page and start again.');
      cb.onError('Transcription engine stopped responding - audio since then is marked as a gap. Stop listening, reload the page, and start again.');
    } else {
      cb.onError('Could not transcribe audio: ' + (e?.message || e)); // frames stay queued and are retried; backlog drops are gap-marked separately
    }
  } finally {
    busy = false; busyFinal = false;
  }
}

async function start(onText, onProgress, onError, onPartial, onStats, onRecover) {
  captureSid++; // every start attempt: stays in lockstep with the app's session counter; any pending recovery from an older capture's drain is now stale
  if (!supported) throw new Error('This browser cannot record audio.');
  if (running) return;
  if (engineDead) { // a stuck engine cannot recover in this page session; do not open another doomed recording
    const msg = 'Transcription engine stopped earlier - reload this page before starting again.';
    setNotice(msg);
    onError?.(msg);
    return;
  }
  onProgress(0);
  if (unknownSavedVariant) { setNotice('Saved model "' + unknownSavedVariant + '" is not in this build - using ' + VARIANTS.multi.label + '.'); unknownSavedVariant = null; }
  const asr = await loadModel(onProgress); // lazy: first call downloads and caches the model
  onProgress(100);
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
    });
  } catch (e) {
    const name = (e && e.name) || '';
    if (name === 'NotAllowedError' || name === 'SecurityError')
      throw new Error('Microphone is blocked. Allow it for this site (lock icon in the browser address bar), then tap the mic again.');
    if (name === 'NotFoundError' || name === 'OverconstrainedError')
      throw new Error('No microphone found on this device. You can type instead.');
    if (name === 'NotReadableError')
      throw new Error('The microphone is busy in another app. Close that app and try again.');
    throw e;
  }
  audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: RATE });
  source = audioCtx.createMediaStreamSource(stream);
  resetSegment();
  committed = []; committedSamples = 0;
  // Capture on the audio thread (AudioWorklet). A ScriptProcessor runs on the main thread, and the WASM
  // decode blocks that thread for seconds, which silently DROPS microphone audio (measured in Chromium).
  let worklet = false;
  try {
    const code = `class Cap extends AudioWorkletProcessor {
      constructor() { super(); this.buf = new Float32Array(2048); this.n = 0; }
      process(inputs) {
        const c = inputs[0] && inputs[0][0];
        if (c) for (let i = 0; i < c.length; i++) {
          this.buf[this.n++] = c[i];
          if (this.n === 2048) { this.port.postMessage(this.buf, [this.buf.buffer]); this.buf = new Float32Array(2048); this.n = 0; }
        }
        return true;
      }
    }
    registerProcessor('voino-cap', Cap);`;
    const url = URL.createObjectURL(new Blob([code], { type: 'application/javascript' }));
    await audioCtx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);
    proc = new AudioWorkletNode(audioCtx, 'voino-cap', { numberOfInputs: 1, numberOfOutputs: 0 });
    proc.port.onmessage = (e) => pushFrame(e.data);
    source.connect(proc);
    worklet = true;
  } catch (_) { /* fall back below */ }
  if (!worklet) {
    proc = audioCtx.createScriptProcessor(BUFFER, 1, 1);
    proc.onaudioprocess = (e) => pushFrame(new Float32Array(e.inputBuffer.getChannelData(0)));
    source.connect(proc);
    proc.connect(audioCtx.destination); // required by some browsers; the output buffer stays silent
  }
  window.voinoCapture.worklet = worklet;
  const cb = { onText, onError, onPartial, onStats, onRecover };
  curCb = cb;
  running = true; capture.samples = 0; capture.t0 = performance.now();
  gaps = []; gapHistory.length = 0; lastDropNotice = 0; // engineDead intentionally survives start(): recovery is reload-only
  spool.length = 0; spooledSamples = 0; emittedGaps.length = 0; // deferred audio never carries into the next capture
  timer = setInterval(() => tick(asr, cb), STEP_MS);
  window.__voinoCb = { asr, cb };
}

let stopInProgress = false; // a second stop waits for the first: concurrent drains would decode on one engine at once
let captureSid = 0;         // capture session id: each start bumps it; recovery payloads carry it so a stale drain cannot rewrite a newer capture's document
async function stop() {
  while (stopInProgress) await new Promise((r) => setTimeout(r, 50));
  stopInProgress = true;
  try {
  running = false;
  clearInterval(timer);
  const { asr, cb } = window.__voinoCb || {};
  // Let an in-flight decode finish and land first (bounded by its own watchdog): voiding it here
  // would only force the drain to re-decode the same segment. The epoch bump after the wait is
  // what guards the next capture.
  while (busy) await new Promise((r) => setTimeout(r, 50));
  decodeEpoch++;
  if (asr && !engineDead) {
    // Drain in bounded segments, in speech order: commit the open segment (chunked at MAX_SEG_S),
    // then decode the FIFO. Speech remains undecoded only if a decode fails, and that is surfaced.
    while (seg.length) commitOpen('stop');
    while (committed.length && !engineDead) {
      const before = committed.length;
      await tick(asr, cb);
      if (committed.length === before) { setNotice('Some audio at the end could not be transcribed - it is marked as a gap in the transcript.'); break; }
    }
  }
  // Anything still undecoded (a decode error broke the drain, or the engine died) is lost, not
  // retained: PCM is not carried into the next capture. Mark each undrained segment's exact span
  // (frame arrival positions), so trimmed silence holes stay unmarked and no loss is silent.
  for (const c of committed) markGap((c[0].seq * BUFFER) / RATE, ((c[c.length - 1].seq + 1) * BUFFER) / RATE);
  if (seg.length && speechSamples > 0) markGap((seg[0].seq * BUFFER) / RATE, ((seg[seg.length - 1].seq + 1) * BUFFER) / RATE);
  flushGaps(cb); // persist any untranscribed interval into the transcript
  // Recover audio the backlog set aside, now that the decoder has the machine to itself. A
  // recovered span rewrites exactly its own gap marker in the transcript; anything not
  // recovered keeps its marker - deferred audio is never marked transcribed on spec.
  // busy stays true through the drain so a racing second stop() waits instead of decoding concurrently.
  if (asr && !engineDead && spool.length) {
    busy = true;
    try {
    setNotice('Transcribing ' + Math.round(spooledSamples / RATE) + 's of audio set aside during overload...');
    const recovered = []; // {a, b, text}
    while (spool.length && !engineDead) {
      const s = spool.shift();
      spooledSamples -= s.frames.reduce((a, f) => a + f.d.length, 0);
      try {
        let watchdog;
        const text = await Promise.race([
          decode(asr, joined(s.frames), true),
          new Promise((_, rej) => { watchdog = setTimeout(() => rej(new Error('decode-timeout')), DECODE_TIMEOUT_MS); }),
        ]).finally(() => clearTimeout(watchdog));
        if (text) {
          recovered.push({ a: s.a, b: s.b, text });
          segTrace.push({ e: 'spool-done', a: Math.round((s.a * RATE) / BUFFER), b: Math.round((s.b * RATE) / BUFFER) - 1 });
        }
      } catch (e) {
        if (e?.message === 'decode-timeout') {
          decodeEpoch++; engineDead = true;
          disposeEngines();
          cb.onError('Transcription engine stopped responding - audio since then is marked as a gap. Stop listening, reload the page, and start again.');
        } // any other failure: this segment keeps its gap marker; try the next
      }
    }
    spool.length = 0; spooledSamples = 0;
    // One grouped rewrite for the whole drain. Each op carries how many copies of its marker
    // string were emitted in this capture (total); the app rewrites only when the transcript
    // still holds exactly that many - an edited, deleted, or duplicated marker count fails safe.
    const surgeries = [];
    for (const m of emittedGaps) {
      const rec = recovered.filter((r) => r.a >= m.a - 0.2 && r.b <= m.b + 0.2).sort((x, y) => x.a - y.a);
      if (!rec.length) continue;
      // Walk the marker's interval in time order: recovered spans become text, the rest stays gaps.
      const parts = [];
      let cur = m.a;
      for (const r of rec) {
        if (r.a > cur + 0.15) parts.push('[gap ' + fmtGap(cur) + '-' + fmtGap(r.a) + ' not transcribed]');
        parts.push(r.text);
        cur = Math.max(cur, r.b);
      }
      if (m.b > cur + 0.15) parts.push('[gap ' + fmtGap(cur) + '-' + fmtGap(m.b) + ' not transcribed]');
      surgeries.push({ str: m.str, nth: m.nth, total: emittedGaps.filter((e) => e.str === m.str).length, repl: parts.join(' ') });
    }
    if (surgeries.length) cb?.onRecover?.(JSON.stringify({ sid: captureSid, ops: surgeries }));
    } finally { busy = false; }
  } else {
    spool.length = 0; spooledSamples = 0;
  }
  proc?.disconnect(); source?.disconnect();
  await audioCtx?.close();
  stream?.getTracks().forEach((t) => t.stop());
  stream = audioCtx = source = proc = null;
  resetSegment();
  committed = []; committedSamples = 0;
  } finally { stopInProgress = false; }
}

function releaseOtherEngines(keep) {
  // Keep at most one local engine resident: engines are not shared across variants and each
  // holds its own WASM memory. Fire-and-forget. Whether a fresh init after a healthy dispose
  // works in-page is measured, not assumed; where it fails, the reload guidance covers it.
  for (const k of Object.keys(asrPromises)) {
    if (k === keep || !asrPromises[k]) continue;
    const p = asrPromises[k];
    asrPromises[k] = null;
    (async () => { try { (await p)?.dispose?.(); } catch (_) {} })();
  }
}

function setVariant(v) {
  if (!VARIANTS[v]) return;
  variant = v;
  try { localStorage.setItem('voinoAsr', v); } catch (_) {}
  releaseOtherEngines(v);
}

// Small "ASR" button (bottom-left) opens a debug panel: pick the local model and see what it returned per decode.
function debugPanel() {
  const css = 'position:fixed;z-index:2147483647;font:12px/1.35 monospace;';
  const btn = document.createElement('button');
  btn.textContent = 'ASR';
  btn.style.cssText = css + 'left:8px;bottom:8px;padding:4px 8px;border-radius:12px;border:1px solid #888;background:#fffc;color:#222;opacity:.75';
  const box = document.createElement('div');
  box.style.cssText = css + 'left:8px;bottom:40px;width:min(92vw,520px);max-height:55vh;overflow:auto;background:#111e;color:#eee;padding:8px;border-radius:8px;display:none';
  const sel = document.createElement('select');
  for (const k of Object.keys(VARIANTS)) { const o = document.createElement('option'); o.value = k; o.textContent = VARIANTS[k].label; sel.appendChild(o); }
  sel.value = variant;
  const status = document.createElement('div'); status.style.cssText = 'color:#fc6;margin-top:4px';
  onNotice = (t) => { status.textContent = t; sel.value = variant; };
  for (const o of sel.options) isInstalled(o.value).then((ok) => { if (!ok) { o.textContent += ' - not installed'; o.disabled = true; if (sel.value === o.value) { setVariant('multi'); sel.value = 'multi'; } } });
  sel.onchange = () => { if (running) { sel.value = variant; alert('Stop listening first, then switch model.'); return; } setVariant(sel.value); };
  const note = document.createElement('div');
  note.textContent = 'Switch model while not listening.';
  note.style.opacity = '.7';
  const rows = document.createElement('div');
  const vin = document.createElement('input');
  vin.placeholder = 'Your words (names, terms), comma separated';
  vin.value = vocab.join(', ');
  vin.style.cssText = 'width:100%;box-sizing:border-box;margin-top:4px';
  vin.onchange = () => setVocabulary(vin.value.split(',').map((w) => w.trim()).filter(Boolean));
  box.append(sel, note, status, vin, rows);
  btn.onclick = () => { box.style.display = box.style.display === 'none' ? 'block' : 'none'; };
  onLog = (e) => {
    const d = document.createElement('div');
    d.style.cssText = 'border-top:1px solid #444;margin-top:4px;padding-top:4px';
    d.textContent = `${e.t} [${e.engine}/${e.lang}] ${e.final ? 'FINAL' : 'part'} ${e.seconds}s ${e.ms}ms rms=${e.rms}${e.dropped ? ' DROPPED' : ''}\nraw: ${JSON.stringify(e.raw)}`;
    rows.prepend(d);
    while (rows.childNodes.length > 40) rows.removeChild(rows.lastChild);
  };
  document.body.append(btn, box);
}
// Debug panel is developer-only: show it after visiting with ?debug=1 (sticks via localStorage).
const debugEnabled = (() => {
  try {
    if (new URLSearchParams(location.search).get('debug') === '1') { localStorage.setItem('voinoDebug', '1'); return true; }
    return localStorage.getItem('voinoDebug') === '1';
  } catch (_) { return false; }
})();
if (debugEnabled && typeof document !== 'undefined') { if (document.body) debugPanel(); else window.addEventListener('DOMContentLoaded', debugPanel); }

function setVocabulary(words) {
  vocab = (words || []).map(String);
  try { localStorage.setItem('voinoVocab', JSON.stringify(vocab)); } catch (_) {}
}

// The Flutter switch's third option: use the Gemini route, or go back to the saved local engine.
function setCloud(on) {
  if (on) { variant = 'gemini'; releaseOtherEngines('gemini'); return; }
  let saved = 'multi';
  try { saved = localStorage.getItem('voinoAsr') || 'multi'; } catch (_) {}
  variant = VARIANTS[saved] && !VARIANTS[saved].cloud ? saved : 'multi';
  releaseOtherEngines(variant);
}

window.voinoWhisper = { supported, start, stop, setVariant, setCloud, setVocabulary, vocabulary: () => vocab.slice(), variants: () => Object.keys(VARIANTS), variant: () => variant, modelId: () => VARIANTS[variant].model, unknownSavedVariant: () => unknownSavedVariant };
// >>> VOINO TEST SEAM - stripped from production builds (tools/strip_test_seams.js)
// Test-only seam for the frame-accounting regression (tools/frame_accounting_test.js run in Node)
// and local browser drivers. Never present in a production artifact.
window.voinoSegTest = {
  pushFrame, tick, stop, commitOpen,
  reset: () => { resetSegment(); committed = []; committedSamples = 0; gaps = []; gapHistory.length = 0; busy = false; busyFinal = false; running = true; capture.samples = 0; decodeEpoch++; engineDead = false; frameSeq = 0; spool.length = 0; spooledSamples = 0; emittedGaps.length = 0; /* dev hook simulates a fresh page */ },
  state: () => ({ seg: seg.length, committed: committed.length, committedSamples, segSamples, inSeg, speechSamples, engineDead }),
  gapHistory: () => gapHistory.map((g) => ({ a: g.a, b: g.b })),
  spool: () => spool.map((s) => ({ a: s.a, b: s.b, samples: s.frames.reduce((n, f) => n + f.d.length, 0) })),
  emittedGaps: () => emittedGaps.map((m) => ({ ...m })),
  trace: () => segTrace.splice(0),
};
// <<< VOINO TEST SEAM
