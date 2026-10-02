// Web-only local speech-to-text: multilingual Whisper tiny in the browser via transformers.js (WASM).
// Hindi + English with per-segment language detection. Hindi output is romanized to English letters (Hinglish).
// The model (about 40 MB quantized) downloads on first use and is cached by the browser.
//
// Live mode: audio is captured continuously (no 5 s recorder chunks). Every STEP_MS the open
// segment is re-transcribed and shown as a PARTIAL result right away; when the speaker pauses
// (or the segment reaches MAX_SEG_S) the segment is transcribed once more and committed as FINAL.
const TRANSFORMERS = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/dist/transformers.min.js';
const MODEL = 'Xenova/whisper-tiny'; // multilingual; the old tiny.en model was English-only
const RATE = 16000;
const STEP_MS = 700; // how often a partial update is attempted (skipped while a decode is running)
const PAUSE_MS = 600; // silence that ends a segment
const MAX_SEG_S = 12; // force-commit long monologues
const MIN_SECONDS = 0.5;
const SILENCE_RMS = 0.004;
const BUFFER = 2048; // 128 ms frames at 16 kHz

const supported = !!(navigator.mediaDevices?.getUserMedia && (window.AudioContext || window.webkitAudioContext));

let asrPromise = null;
let TensorCls = null;
let segLang = null; // 'en' | 'hi' for the open segment, detected once per segment
let stream = null, audioCtx = null, source = null, proc = null, timer = null;
let running = false, busy = false;
let seg = []; // Float32Array frames of the open segment
let segSamples = 0, speechSamples = 0, lastSpeechAt = 0, lastPartial = '';

const HALLUCINATIONS = /^(?:thanks for watching|thank you\.?|you|bye\.?|\.+)$/i;

function loadModel(onProgress) {
  if (!asrPromise) {
    asrPromise = (async () => {
      const { pipeline, env, Tensor } = await import(TRANSFORMERS);
      TensorCls = Tensor;
      env.allowLocalModels = false;
      env.useBrowserCache = true;
      const files = {};
      return pipeline('automatic-speech-recognition', MODEL, {
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
      asrPromise = null; // allow retry
      throw e;
    });
  }
  return asrPromise;
}

function joined() {
  const out = new Float32Array(segSamples);
  let o = 0;
  for (const f of seg) { out.set(f, o); o += f.length; }
  return out;
}

function resetSegment() {
  seg = []; segSamples = 0; speechSamples = 0; lastPartial = ''; segLang = null;
}

// transformers.js defaults to English when no language is given, so detect it ourselves:
// one decoder step after the start token, then compare the <|hi|> and <|en|> logits.
async function detectLanguage(asr, samples) {
  try {
    const feats = await asr.processor(samples);
    const ids = asr.tokenizer.model.tokens_to_ids;
    const sot = ids.get('<|startoftranscript|>'), en = ids.get('<|en|>'), hi = ids.get('<|hi|>');
    const out = await asr.model({
      input_features: feats.input_features,
      decoder_input_ids: new TensorCls('int64', BigInt64Array.from([BigInt(sot)]), [1, 1]),
    });
    const lg = out.logits.data;
    return lg[hi] > lg[en] ? 'hi' : 'en';
  } catch (_) {
    return 'en';
  }
}

async function decode(asr, samples) {
  segLang ??= await detectLanguage(asr, samples);
  const out = await asr(samples, { task: 'transcribe', language: segLang });
  const raw = (out?.text || '').trim();
  const text = window.voinoRomanize ? window.voinoRomanize(raw) : raw;
  return HALLUCINATIONS.test(text) ? '' : text;
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
    const text = await decode(asr, samples);
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
  proc = audioCtx.createScriptProcessor(BUFFER, 1, 1);
  resetSegment();
  proc.onaudioprocess = (e) => {
    if (!running) return;
    const data = new Float32Array(e.inputBuffer.getChannelData(0));
    let sum = 0;
    for (let i = 0; i < data.length; i++) sum += data[i] * data[i];
    if (Math.sqrt(sum / data.length) >= SILENCE_RMS) { lastSpeechAt = performance.now(); speechSamples += data.length; }
    seg.push(data); segSamples += data.length;
  };
  source.connect(proc);
  proc.connect(audioCtx.destination); // required by some browsers; the output buffer stays silent
  const cb = { onText, onError, onPartial, onStats };
  running = true;
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

window.voinoWhisper = { supported, start, stop };
