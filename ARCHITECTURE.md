# Voino architecture

Status: planning document, September 2026. "Implemented" describes the prototype in this repository. "Proposed" is not shipped.

## Product goal

A phone-first listening and editing tool for lectures, meetings, and discussions. The target experience is: listen in real time, capture a transcript, turn it into useful notes, and edit/arrange the result. A full, faithful session summary is the desired product direction, not a claim about the current rule-based prototype.

## Implemented prototype

```
Microphone -> browser SpeechRecognition -> editable transcript
                                  |                |
                                  |          browser localStorage
                                  v
                   deterministic sentence extraction
                         /                   \
                  key-point sentences     explicit to-do sentences
                         \                   /
                        editable notes + spatial card board
                       (colors, arrows, circles, boxes)
                                  |
                         localStorage + text/JSON export
```

- Client: static HTML/CSS/JavaScript, no app backend or sign-in. Board uses DOM cards and SVG for connectors and shapes. There is no bundled model or paid API.
- Speech: the browser's SpeechRecognition API where supported. Browser/vendor support and network behavior vary. Speech may be processed by the browser vendor. The app does not store an audio file. Request consent before capturing anyone else's voice.
- Extraction: `src/notes.js` splits the corrected transcript into sentences and recognizes explicit action phrases. It keeps source wording; it does not infer every important point or generate a full AI summary. The user's review is essential.
- Board: cards are editable. The user can add cards, recolor them, connect them with arrows, and draw manual circles/boxes. These are not automatically generated charts or Excalidraw files.
- Local state: one draft in browser localStorage (`voino-draft-v1`), including transcript, notes, cards, positions, connections and shapes. Browser storage may be cleared or quota-limited; export to preserve important work. No sync across devices.
- Failure path: if speech recognition is unavailable, denied, interrupted or offline, paste/type a transcript. Once the page is loaded, extraction, editing, shapes, arrows and local saves work without network. Reopening a closed tab offline is not guaranteed; there is no service worker yet.

## Proposed product layers, not shipped

1. **Reliable baseline on capable browsers:** improve deterministic extraction and transcript controls without an API cost. A rule-based extractor is not a semantic summary and cannot be marketed as one. Test on actual low/mid-range phones, long sessions, interruptions, and different accents/languages before making compatibility claims.
2. **Optional AI summarization:** evaluate model/service paths for a true source-linked summary. Any hosted API (Gemini, Groq, OpenRouter or another service) has quotas, cost or access policies; a shared key is not unlimited free. Never ship a key in browser code. A server-side proxy with authentication, request limits, abuse protection, deletion policy and consent would be required. No API/provider is selected yet. A user-supplied API key is a separate UX/security decision, not assumed.
3. **On-device AI research:** WebLLM/WebGPU may run locally on select phones, but a 1B model can require roughly 705 MB initial download and significant GPU/memory. Some Android GPU/driver combinations fail even with WebGPU present. It is not currently the default or a guaranteed mainstream path. Device detection, explicit download consent, storage checks, cancellation and a benchmark gate are required before enabling it. See [WebLLM](https://webllm.mlc.ai/), [model repository](https://huggingface.co/mlc-ai/Llama-3.2-1B-Instruct-q4f16_1-MLC/tree/main), [Android bug](https://github.com/mlc-ai/web-llm/issues/836).
4. **Local speech research:** on-device, low-latency transcription is a separate goal. It needs a supported model/runtime, permissions, language support, actual device benchmarks and a clear storage cost. Chrome's built-in foundation-model Summarizer API does not currently support Android/iOS Chrome; do not conflate it with browser SpeechRecognition. [Chrome API requirements](https://developer.chrome.com/docs/ai/summarizer-api).
5. **Future collaboration/export:** speaker-aware tasks only with consent and tested attribution; shared boards require accounts/sync/conflict handling. Excalidraw file export is not implemented. Auto-generated graphs from transcript data require structured parsing, source checking and visual testing.

## Privacy and trust boundaries

- "Notes saved locally" means Voino's own draft and board state stay in the browser. It does **not** mean speech stays on-device: the browser's recognition service may process audio remotely.
- If hosted AI is added, show clearly when and what transcript text will be sent, get meaningful user consent, avoid exposing other attendees' sensitive speech, and define retention/deletion behavior before public use.
- AI or rules output must be labeled with its method. Preserve and link to source transcript spans where possible. Do not fabricate missing points, speakers, owners, decisions or numbers. The user edits and confirms before relying on it.
- No repo, browser bundle, screenshots or logs should contain persistent API secrets.

## Next decisions for Sanskar

- Which actual phone/browser is the demo target, and does live speech recognition work there with the expected network?
- What does a useful *full-session* summary look like (short prose, sections, decisions, questions, action owners), and what errors are unacceptable?
- Is the first product a single-user web app, or is cross-device sync needed soon? That changes privacy and backend scope.
- For a possible AI tier, which tradeoff matters most: no cost, broad phone coverage, privacy, or summary quality? A hosted free quota cannot guarantee unlimited use across a public audience; a local model cannot guarantee small download and broad compatibility today.

## Verification before claims

- Test voice capture on the actual phone, with microphone permission and internet, then test a long session and an interruption. Record browser version, OS, RAM/storage if available, and observed errors.
- Test notes against at least three real consented transcripts. Measure omitted and false key points/action items; show the source words for every card.
- Test phone board touch editing, arrows, shapes, export, refresh, and offline *after loading*. Do not claim offline listening or full-session summary from these tests.
