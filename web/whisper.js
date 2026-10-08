// Web-only local speech-to-text: multilingual Whisper tiny in the browser via transformers.js (WASM).
// Hindi + English with per-segment language detection. Hindi output is romanized to English letters (Hinglish).
// The model (about 40 MB quantized) downloads on first use and is cached by the browser.
//
// Live mode: audio is captured continuously (no 5 s recorder chunks). Every STEP_MS the open
// segment is re-transcribed and shown as a PARTIAL result right away; when the speaker pauses
// (or the segment reaches MAX_SEG_S) the segment is transcribed once more and committed as FINAL.
const TRANSFORMERS = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/dist/transformers.min.js';
// Local engines. 'multi' is the stock multilingual tiny (MIT). 'hinglish' is a Hinglish fine-tune of
// whisper-tiny (abhishekgautamm/whisper-tiny-hinglish, NO LICENSE STATED on its page) converted to ONNX
// and hosted with this app. It is TEST ONLY: never the default, do not ship until the author adds a license.
const VARIANTS = {
  multi: { label: 'Stock tiny (MIT)', model: 'Xenova/whisper-tiny', lang: 'hi' },
  hinglish: { label: 'Hinglish tiny (test only)', model: 'hinglish', local: true, lang: null },
  gemini: { label: 'Gemini (cloud, free tier)', cloud: true, lang: null },
  vaani: { label: 'Vaani Hindi tiny (Apache-2.0)', model: 'vaani', local: true, lang: 'hi' },
};
let variant = (() => { try { const v = localStorage.getItem('voinoAsr'); return VARIANTS[v] ? v : 'multi'; } catch (_) { return 'multi'; } })();
const asrPromises = {};
const RATE = 16000;
const STEP_MS = 700; // how often a partial update is attempted (skipped while a decode is running)
const PAUSE_MS = 500; // silence that ends a segment
const MAX_SEG_S = 8; // long monologues are split at the quietest point instead of growing
const PRE_ROLL = 3; // frames (about 0.4 s) kept from before speech starts so first syllables survive
const MIN_SECONDS = 0.5;
const SILENCE_RMS = 0.004;
const BUFFER = 2048; // 128 ms frames at 16 kHz

const supported = !!(navigator.mediaDevices?.getUserMedia && (window.AudioContext || window.webkitAudioContext));

let TensorCls = null;
let stream = null, audioCtx = null, source = null, proc = null, timer = null;
let running = false, busy = false;
let seg = []; // frames {d: Float32Array, rms, sp} of the open segment (speech started, not yet committed)
let pre = []; // recent frames while idle
let inSeg = false;
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
      const r = await fetch(base + v.model + '/config.json', { cache: 'no-cache' });
      const t = r.headers.get('content-type') || '';
      if (!r.ok || t.includes('html')) return false;
      const p = await fetch(base + v.model + '/onnx/' + PARTS[0], { method: 'HEAD', cache: 'no-cache' });
      return p.ok && !(p.headers.get('content-type') || '').includes('html');
    } catch (_) { return false; }
  })();
  return availability[name];
}
let notice = '';
let onNotice = null;
function setNotice(t) { notice = t; onNotice?.(t); if (t) console.warn('voino asr:', t); }

// The decoder is split in parts (GitHub web uploads are capped at 25 MB per file); put it back together on load.
const PARTS = ['decoder_model_merged_quantized.onnx.part1', 'decoder_model_merged_quantized.onnx.part2', 'decoder_model_merged_quantized.onnx.part3'];
function hinglishCache(base) {
  return {
    async match(req) {
      const url = typeof req === 'string' ? req : req.url;
      const m = url.match(/\/(hinglish|vaani)\/onnx\/decoder_model_merged_quantized\.onnx$/);
      if (!m) return undefined;
      const bufs = await Promise.all(PARTS.map(async (n) => {
        const r = await fetch(base + m[1] + '/onnx/' + n);
        if (!r.ok) throw new Error('model part missing: ' + n);
        return r.arrayBuffer();
      }));
      return new Response(new Blob(bufs), { status: 200, headers: { 'content-type': 'application/octet-stream' } });
    },
    async put() {},
  };
}

async function loadModel(onProgress, name = variant) {
  if (VARIANTS[name].cloud) return null; // nothing to download; the local engine loads only if the cloud is unavailable
  if (!(await isInstalled(name))) {
    const missing = VARIANTS[name].label;
    if (name === variant) setVariant('multi');
    name = 'multi';
    setNotice(`${missing} is not installed in this build; using ${VARIANTS.multi.label}.`);
  }
  const v = VARIANTS[name];
  if (!asrPromises[name]) {
    asrPromises[name] = (async () => {
      const { pipeline, env, Tensor } = await import(TRANSFORMERS);
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
      return pipeline('automatic-speech-recognition', v.model, {
        dtype: 'q8',
        progress_callback: (p) => {
          if (p.status !== 'progress' || !p.total) return;
          files[p.file] = { loaded: p.loaded, total: p.total };
          const all = Object.values(files);
          const total = all.reduce((a, f) => a + f.total, 0);
          const loaded = all.reduce((a, f) => a + f.loaded, 0);
          onProgress(Math.min(99, Math.round((loaded / total) * 100)));
        },
      });
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
    t: new Date().toLocaleTimeString(), engine, lang: lang || 'auto', final: isFinal,
    seconds: +(samples.length / RATE).toFixed(1), ms: Math.round(performance.now() - t0),
    rms: +rms.toFixed(4), raw, shown: halluc ? '' : text, dropped: halluc,
  };
  log.push(entry); if (log.length > 200) log.shift();
  onLog?.(entry);
  return halluc ? '' : text;
}

// Index of the quietest frame in the second half of the open segment: a safe place to cut a long monologue.
function quietestSplit() {
  const lo = Math.max(2, Math.floor(seg.length / 2));
  const hi = seg.length - 2;
  let best = -1, bestRms = Infinity;
  for (let i = lo; i <= hi; i++) if (seg[i].rms < bestRms) { bestRms = seg[i].rms; best = i; }
  return best;
}

async function tick(asr, cb, force = false) {
  if (busy || !inSeg) return;
  if (speechSamples < RATE * MIN_SECONDS && !force) {
    if (performance.now() - lastSpeechAt > 1500) resetSegment(); // a click or cough, not speech
    return;
  }
  if (!speechSamples) { resetSegment(); return; }
  const paused = performance.now() - lastSpeechAt > PAUSE_MS;
  const tooLong = segSamples > RATE * MAX_SEG_S;
  const isFinal = force || paused || tooLong;
  // Frames to decode: all of them, minus trailing silence on a pause; up to the quietest frame on a forced split.
  let take = seg.length;
  if (paused || force) {
    let last = seg.length - 1;
    while (last > 0 && !seg[last].sp) last--;
    take = Math.min(seg.length, last + 3);
  } else if (tooLong) {
    const q = quietestSplit();
    if (q > 0) take = q;
  }
  const frames = seg.slice(0, take);
  busy = true;
  try {
    const t0 = performance.now();
    const text = await decode(asr, joined(frames), isFinal);
    const ms = Math.round(performance.now() - t0);
    cb.onStats?.(ms, frames.length * BUFFER / RATE, isFinal);
    if (isFinal) {
      // Keep frames that arrived while decoding; drop only what was transcribed.
      seg = seg.slice(take);
      recount();
      lastPartial = '';
      inSeg = seg.some((f) => f.sp);
      if (!inSeg) { seg = []; segSamples = 0; speechSamples = 0; }
      cb.onPartial?.('');
      if (text) cb.onText(text);
    } else if (text && text !== lastPartial) {
      lastPartial = text;
      cb.onPartial?.(text);
    }
  } catch (e) {
    cb.onError('Could not transcribe audio: ' + (e?.message || e));
  } finally {
    busy = false;
  }
}

async function start(onText, onProgress, onError, onPartial, onStats) {
  if (!supported) throw new Error('This browser cannot record audio.');
  if (running) return;
  onProgress(0);
  const asr = await loadModel(onProgress); // lazy: first call downloads and caches the model
  onProgress(100);
  stream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
  });
  audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: RATE });
  source = audioCtx.createMediaStreamSource(stream);
  resetSegment();
  const onFrame = (data) => {
    if (!running) return;
    let sum = 0;
    for (let i = 0; i < data.length; i++) sum += data[i] * data[i];
    const rms = Math.sqrt(sum / data.length);
    const sp = rms >= SILENCE_RMS;
    const fr = { d: data, rms, sp };
    if (sp) lastSpeechAt = performance.now();
    if (!inSeg) {
      if (sp) { inSeg = true; seg = pre.concat([fr]); pre = []; recount(); }
      else { pre.push(fr); if (pre.length > PRE_ROLL) pre.shift(); }
    } else {
      seg.push(fr); segSamples += data.length; if (sp) speechSamples += data.length;
    }
    capture.samples += data.length;
    if (capture.keep) capture.keep.push(data);
  };
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
    proc.port.onmessage = (e) => onFrame(e.data);
    source.connect(proc);
    worklet = true;
  } catch (_) { /* fall back below */ }
  if (!worklet) {
    proc = audioCtx.createScriptProcessor(BUFFER, 1, 1);
    proc.onaudioprocess = (e) => onFrame(new Float32Array(e.inputBuffer.getChannelData(0)));
    source.connect(proc);
    proc.connect(audioCtx.destination); // required by some browsers; the output buffer stays silent
  }
  window.voinoCapture.worklet = worklet;
  const cb = { onText, onError, onPartial, onStats };
  curCb = cb;
  running = true; capture.samples = 0; capture.t0 = performance.now();
  timer = setInterval(() => tick(asr, cb), STEP_MS);
  window.__voinoCb = { asr, cb };
}

async function stop() {
  running = false;
  clearInterval(timer);
  const { asr, cb } = window.__voinoCb || {};
  while (busy) await new Promise((r) => setTimeout(r, 50));
  if (asr) await tick(asr, cb, true); // commit the last partial segment
  proc?.disconnect(); source?.disconnect();
  await audioCtx?.close();
  stream?.getTracks().forEach((t) => t.stop());
  stream = audioCtx = source = proc = null;
  resetSegment();
}

function setVariant(v) {
  if (!VARIANTS[v]) return;
  variant = v;
  try { localStorage.setItem('voinoAsr', v); } catch (_) {}
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
  note.textContent = 'Hinglish tiny has no stated license: test only. Switch model while not listening.';
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
if (typeof document !== 'undefined') { if (document.body) debugPanel(); else window.addEventListener('DOMContentLoaded', debugPanel); }

function setVocabulary(words) {
  vocab = (words || []).map(String);
  try { localStorage.setItem('voinoVocab', JSON.stringify(vocab)); } catch (_) {}
}

// The Flutter switch's third option: use the Gemini route, or go back to the saved local engine.
function setCloud(on) {
  if (on) { variant = 'gemini'; return; }
  let saved = 'multi';
  try { saved = localStorage.getItem('voinoAsr') || 'multi'; } catch (_) {}
  variant = VARIANTS[saved] && !VARIANTS[saved].cloud ? saved : 'multi';
}

window.voinoWhisper = { supported, start, stop, setVariant, setCloud, setVocabulary, vocabulary: () => vocab.slice(), variants: () => Object.keys(VARIANTS) };
