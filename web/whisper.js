// Web-only local speech-to-text: Whisper tiny.en in the browser via transformers.js (WASM).
// The model (about 40 MB quantized) downloads on first use and is cached by the browser.
// Audio is recorded in 5-second standalone chunks, each transcribed separately.
const TRANSFORMERS = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1/dist/transformers.min.js';
const MODEL = 'Xenova/whisper-tiny.en';
const CHUNK_MS = 5000;
const MIN_SECONDS = 0.6;
const SILENCE_RMS = 0.004;

const supported = !!(navigator.mediaDevices?.getUserMedia && window.MediaRecorder && (window.AudioContext || window.webkitAudioContext));

let asrPromise = null;
let stream = null;
let running = false;
let chain = Promise.resolve();
let audioCtx = null;
let loopDone = Promise.resolve();

function loadModel(onProgress) {
  if (!asrPromise) {
    asrPromise = (async () => {
      const { pipeline, env } = await import(TRANSFORMERS);
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

function recordOnce() {
  return new Promise((resolve) => {
    const rec = new MediaRecorder(stream);
    const parts = [];
    rec.ondataavailable = (e) => e.data.size && parts.push(e.data);
    rec.onstop = () => resolve(new Blob(parts, { type: rec.mimeType }));
    rec.start();
    const timer = setTimeout(() => rec.state === 'recording' && rec.stop(), CHUNK_MS);
    // Stop early when the user stops listening.
    const watch = setInterval(() => {
      if (!running && rec.state === 'recording') rec.stop();
      if (rec.state === 'inactive') {
        clearInterval(watch);
        clearTimeout(timer);
      }
    }, 100);
  });
}

async function toSamples(blob) {
  audioCtx ??= new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 16000 });
  const buf = await audioCtx.decodeAudioData(await blob.arrayBuffer());
  return buf.getChannelData(0);
}

async function transcribe(blob, asr, onText, onError) {
  try {
    const samples = await toSamples(blob);
    if (samples.length < 16000 * MIN_SECONDS) return;
    let sum = 0;
    for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
    if (Math.sqrt(sum / samples.length) < SILENCE_RMS) return; // skip silence, avoids hallucinated text
    const out = await asr(samples);
    const text = (out?.text || '').trim();
    if (text) onText(text);
  } catch (e) {
    onError('Could not transcribe audio: ' + (e?.message || e));
  }
}

async function start(onText, onProgress, onError) {
  if (!supported) throw new Error('This browser cannot record audio.');
  if (running) return;
  onProgress(0);
  const asr = await loadModel(onProgress); // lazy: first call downloads and caches the model
  onProgress(100);
  stream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
  });
  running = true;
  loopDone = (async () => {
    while (running) {
      const blob = await recordOnce();
      if (blob.size) chain = chain.then(() => transcribe(blob, asr, onText, onError));
    }
  })();
}

async function stop() {
  running = false;
  await loopDone; // waits for the final partial chunk
  await chain; // and for every queued transcription
  stream?.getTracks().forEach((t) => t.stop());
  stream = null;
}

window.voinoWhisper = { supported, start, stop };
