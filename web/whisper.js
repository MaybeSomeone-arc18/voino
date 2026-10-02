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
  vaani: { label: 'Vaani Hindi tiny (Apache-2.0)', model: 'vaani', local: true, lang: 'hi' },
};
let variant = (() => { try { const v = localStorage.getItem('voinoAsr'); return VARIANTS[v] ? v : 'multi'; } catch (_) { return 'multi'; } })();
const asrPromises = {};
const RATE = 16000;
const STEP_MS = 700; // how often a partial update is attempted (skipped while a decode is running)
const PAUSE_MS = 600; // silence that ends a segment
const MAX_SEG_S = 12; // force-commit long monologues
const MIN_SECONDS = 0.5;
const SILENCE_RMS = 0.004;
const BUFFER = 2048; // 128 ms frames at 16 kHz

const supported = !!(navigator.mediaDevices?.getUserMedia && (window.AudioContext || window.webkitAudioContext));

let TensorCls = null;
let stream = null, audioCtx = null, source = null, proc = null, timer = null;
let running = false, busy = false;
let seg = []; // Float32Array frames of the open segment
let segSamples = 0, speechSamples = 0, lastSpeechAt = 0, lastPartial = '';

const HALLUCINATIONS = /^(?:thanks for watching|thank you\.?|you|bye\.?|\.+)$/i;

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

function loadModel(onProgress) {
  const v = VARIANTS[variant];
  if (!asrPromises[variant]) {
    asrPromises[variant] = (async () => {
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
      delete asrPromises[variant]; // allow retry
      throw e;
    });
  }
  return asrPromises[variant];
}

function joined() {
  const out = new Float32Array(segSamples);
  let o = 0;
  for (const f of seg) { out.set(f, o); o += f.length; }
  return out;
}

function resetSegment() {
  seg = []; segSamples = 0; speechSamples = 0; lastPartial = '';
}

// Every decode is recorded here (window.voinoLog) and shown in the ASR debug panel.
const log = (window.voinoLog = []);
const capture = (window.voinoCapture = { samples: 0, t0: 0 }); // audio actually received vs wall clock (detects dropped audio)
let onLog = null;

async function decode(asr, samples, isFinal) {
  const v = VARIANTS[variant];
  const t0 = performance.now();
  const lang = v.lang;
  const opts = { task: 'transcribe' };
  if (lang) opts.language = lang;
  const out = await asr(samples, opts);
  const raw = (out?.text || '').trim();
  const text = window.voinoRomanize ? window.voinoRomanize(raw) : raw;
  const halluc = HALLUCINATIONS.test(text);
  let rms = 0;
  for (let i = 0; i < samples.length; i++) rms += samples[i] * samples[i];
  rms = Math.sqrt(rms / samples.length);
  const entry = {
    t: new Date().toLocaleTimeString(), engine: variant, lang: lang || 'auto', final: isFinal,
    seconds: +(samples.length / RATE).toFixed(1), ms: Math.round(performance.now() - t0),
    rms: +rms.toFixed(4), raw, shown: halluc ? '' : text, dropped: halluc,
  };
  log.push(entry); if (log.length > 200) log.shift();
  onLog?.(entry);
  return halluc ? '' : text;
}

async function tick(asr, cb, force = false) {
  if (busy) return;
  if (speechSamples < RATE * MIN_SECONDS) {
    if (!speechSamples && segSamples > RATE * 2) resetSegment(); // long silence, drop it
    return;
  }
  const paused = performance.now() - lastSpeechAt > PAUSE_MS;
  const isFinal = force || paused || segSamples > RATE * MAX_SEG_S;
  busy = true;
  const samples = joined();
  const taken = segSamples;
  try {
    const t0 = performance.now();
    const text = await decode(asr, samples, isFinal);
    const ms = Math.round(performance.now() - t0);
    cb.onStats?.(ms, taken / RATE, isFinal);
    if (window.voinoDebug) console.debug('voino asr', { ms, audioSeconds: +(taken / RATE).toFixed(1), isFinal });
    if (isFinal) {
      // Keep audio that arrived while decoding; drop only what was transcribed.
      let drop = taken, kept = [];
      for (const f of seg) { if (drop >= f.length) drop -= f.length; else kept.push(f); }
      seg = kept; segSamples = seg.reduce((a, f) => a + f.length, 0); speechSamples = 0; lastPartial = '';
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
    if (Math.sqrt(sum / data.length) >= SILENCE_RMS) { lastSpeechAt = performance.now(); speechSamples += data.length; }
    seg.push(data); segSamples += data.length;
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
  sel.onchange = () => { if (running) { sel.value = variant; alert('Stop listening first, then switch model.'); return; } setVariant(sel.value); };
  const note = document.createElement('div');
  note.textContent = 'Hinglish tiny has no stated license: test only. Switch model while not listening.';
  note.style.opacity = '.7';
  const rows = document.createElement('div');
  box.append(sel, note, rows);
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

window.voinoWhisper = { supported, start, stop, setVariant, variants: () => Object.keys(VARIANTS) };
