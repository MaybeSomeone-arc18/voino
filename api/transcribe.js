'use strict';
// POST /api/transcribe  { audio: base64 WAV (16 kHz mono), vocab?: string[] }  ->  { text }
// Errors: 429 quota_exhausted / rate_limited (the app falls back to on-device), 503 not_configured / upstream_unavailable.
// The key comes from the GEMINI_API_KEY environment variable and never reaches the client.
// Note: on Google's free tier the audio may be used to improve their products; do not send confidential audio.
module.exports = require('./_lib/asr').makeHandler();
