# Voino

**Listen. Understand. Edit.** Voino turns what is said in meetings, lectures and discussions into editable notes and a hand-drawn, Excalidraw-style board you can rearrange and share.

Built with Flutter for **Android** and the **web**. Local-first: notes work with no account, no server and no API key. AI summaries are optional.

> **Status: prototype.** Unit and widget tests pass (41 Flutter, 12 Node). The web build is verified in a browser. Live speech on a real phone, the Android build and the Vercel deployment have not been verified end to end yet. See [Known limitations](#known-limitations).

## How it works

```
Speak or type ──► editable transcript ──► notes ──► visual board ──► edit, save, share
                                            │
                     local extractor (default, offline)
                     Gemini with your own key (optional)
                     hosted summarizer on Vercel (optional)
```

1. **Listen.** Tap the mic and talk. Words appear live as they are recognized. Or tap *Type instead* and paste a transcript.
2. **Notes.** Review the transcript, fix mistakes, then make the board. Notes are labelled "Rule-based extract" or "AI summary" so you always know how they were made.
3. **Board.** Notes become a mind-map you can edit like a whiteboard, then save as a file for someone else to open and edit.

## Features

### Capture
- **Android:** the device's speech recognizer (`speech_to_text`).
- **Web:** choose **Whisper (local)** or **Device speech**. Whisper runs `whisper-tiny.en` in your browser (about 40 MB, downloaded once and cached, audio never leaves your machine). It is the default when the browser has no speech recognizer of its own.
- **Type or paste** always works. Typed text is never presented as recognized speech.
- **Clear all** wipes the transcript, notes, board and any active recording in one tap.

### Notes
- **Local by default.** Removes filler words, ranks sentences by keyword weight, groups related points into topics, links neighbouring points and pulls out action items. It keeps your original wording and never invents content. It selects sentences; it does not rewrite them.
- **Optional Gemini summaries with your own key.** Open settings, paste one or more API keys (one per line), switch it on and press *Test*. Voino rotates through your keys and falls back to local notes if a request fails. Keys are kept in secure storage on your device and go only to Google.
- **Optional hosted summarizer.** A Vercel function (`api/summarize.js`) can summarize with server-side keys, so demo visitors need no key. It is off by default. Your own keys are tried first.
- **Consent first.** Voino asks before a transcript leaves your device, separately for Gemini and for the hosted summarizer.

### Board
- **Auto layout:** a central title card, one boxed group per topic around it, rose *To do* cards, mint point cards, labelled arrows for relationships, and circles on the key point and any decisions. Cards never overlap.
- **Excalidraw-style canvas:** hand-drawn strokes and font, dashed sketchy shapes, dot grid, pan and zoom.
- **Edit everything:** drag cards and shapes, resize shapes, double-tap to edit text or label an arrow, change card colors (◐), delete (×), add notes, connect cards, draw boxes and circles.
- **Undo** (up to 60 steps), **Delete selected**, and keyboard shortcuts (Delete, Backspace, Ctrl+Z) on desktop.
- **Save and share:** *Save board .json* downloads a file; *Open board file* (or *Paste board JSON*) loads one. Imported files are validated and clamped before use, so a shared board is safe to open.

## Quick start

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ^3.12) and, for Android, a device or emulator.

```bash
flutter pub get
flutter run -d chrome     # web
flutter run               # connected Android device
```

Grant the microphone permission when asked. Speech may need internet, depending on the recognizer.

### Tests

```bash
flutter analyze
flutter test                      # notes, board layout, Gemini client, board UI interactions
node --test tests/api.test.js     # hosted summarizer: key rotation, validation, rate limit
```

### Build

```bash
flutter build apk --debug         # Android (com.maybesomeone.voino)
flutter build web --release       # web, output in build/web
```

## Optional: Gemini and the hosted summarizer

**With your own key (no server needed):** open the settings icon in the app, paste your key(s), enable *Use Gemini*. Nothing else to deploy.

**Hosted summarizer (for demos):** deploy to Vercel and set these environment variables in the project settings:

| Variable | Purpose |
|---|---|
| `GEMINI_KEYS` | Comma-separated Gemini API keys (`GEMINI_API_KEYS` also works). Rotated round-robin. |
| `GEMINI_MODEL` | Optional. Defaults to `gemini-2.5-flash`. |
| `ALLOWED_ORIGIN` | Optional CORS origin. Defaults to `*`. |

Then users switch on *Use Voino's hosted summarizer* in settings. For Android, point the app at your deployment:

```bash
flutter build apk --dart-define=VOINO_API_URL=https://<your-app>.vercel.app/api/summarize
```

How the function protects itself: transcripts are capped at 12,000 characters, requests are limited to 6 per minute and 60 per day per IP, errors never echo keys or transcript text, and the model is instructed to use only what was said. The server then removes points, actions and summary sentences containing numbers the transcript never said, and drops owners nobody named. The rate limit is per serverless instance, so it is a guard against casual abuse, not a hard quota. Never put keys in the app or the repo.

## Deploy to Vercel

`vercel.json` builds the Flutter web app (it clones stable Flutter, so the first build takes several minutes) and serves `api/summarize.js` as a function. Import the repo in Vercel, add the environment variables above, and deploy.

## Project layout

```
lib/
  main.dart            UI: Listen / Notes / Board tabs, speech, settings
  logic.dart           speech stitching, Note model, local extractive notes
  gemini.dart          Gemini client, hosted-summarizer client, fallback order
  board.dart           card/link/shape models, notes -> board layout, safe JSON import
  board_controller.dart  board state, tools, selection, undo
  board_view.dart      Excalidraw-style canvas and toolbar
  rough.dart           hand-drawn stroke helpers
  live_transcript.dart live transcript panel while listening
  settings.dart        keys and consent flags (secure storage)
  whisper_web.dart     web-only bridge to web/whisper.js (whisper_stub.dart elsewhere)
web/whisper.js         in-browser Whisper via transformers.js
api/summarize.js       Vercel function (logic in api/_lib/core.js)
test/  tests/          Flutter tests and Node tests
```

More detail: [ARCHITECTURE.md](ARCHITECTURE.md).

## Privacy

- Notes, the board and the transcript stay on your device unless you turn on an AI option. Nothing is saved between sessions except settings, so save the board file to keep your work.
- The device or browser speech recognizer may send audio to its vendor. Whisper on web does not.
- Turning on Gemini or the hosted summarizer sends the transcript to Google (through Voino's server for the hosted option, which does not store it). Google's own terms apply.
- **Ask permission before recording other people.**

## Known limitations

- Not yet verified on a real phone: live speech, the Android build, and the board's touch interactions.
- The Vercel deployment has not been run yet, and Whisper's first load needs the internet (transformers.js from jsDelivr, the model from Hugging Face).
- Whisper records in 5-second chunks, so a word can be clipped at a chunk boundary.
- Local notes can miss points. They are extracts, not a summary, so check them against the transcript.
- AI summaries can still be wrong. Review before relying on them.
- No accounts, sync or offline app install. Android has no on-device speech model or LLM.

## License

MIT. See [LICENSE](LICENSE). The Caveat font is licensed under the SIL Open Font License.

## Android RevenueCat Test Store demo

This debug Android build uses `purchases_flutter` and the `voino_pro` entitlement.
Listening, typing, notes, board editing and text export stay free. Android board
JSON save, copy, open and pasted import require an active entitlement returned by
RevenueCat. Web remains free and does not configure native purchases. No history
or cloud sync is implemented.

Build a debug APK with your project's public Test Store SDK key (not a secret API key):

```sh
flutter pub get
flutter test
flutter build apk --debug --dart-define=REVENUECAT_TEST_STORE_KEY=YOUR_PUBLIC_TEST_STORE_SDK_KEY
```

Configure the Test Store's current offering/package to grant `voino_pro`. Tap
**Test Pro**, review the actual package metadata, then use the sandbox modal to
simulate cancel/failure first and success last. Cancel/failure must leave board
files locked. Success must return active `voino_pro`, enable save/open, and survive
CustomerInfo refresh. Test **Restore test purchases**, then expiry/revocation.
Test subscriptions expire quickly; the entitlement is checked again before file
operations and on app resume. Connection failure locks only board files.

This is sandbox billing with no real charge or finalized production pricing.
It is not a Google Play release: release builds deliberately refuse this Test
Store setup. A production billing configuration and release/signing review are
separate work. Test Store acceptance for Shipaton has not been confirmed by the
organizer. Real-device purchase and save/open acceptance must be recorded before
claiming those paths work.
