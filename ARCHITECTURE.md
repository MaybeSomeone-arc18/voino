# Voino architecture

Status: September 2026. Flutter app (Android + web on Vercel), local-first.

## Flow

```
Mic -> speech_to_text (device/browser recognizer) -> editable transcript
                                   |
                  +----------------+-----------------+
                  |                                  |
        local extractor (default)         Gemini (optional, user's key)
        lib/logic.dart                    lib/gemini.dart
                  \                                  /
                   Note {summary, points, actions, topics, links, keyPoint}
                                   |
                        buildBoard() -> lib/board.dart
                                   |
      title card + boxed topic columns + "To do" column + labelled arrows + key circle
                                   |
              editable board: drag, edit, recolor, connect, draw, import/export JSON
```

## Modules
- `lib/logic.dart`: speech stitching, `Note` model, local extractive notes (filler removal, keyword-weighted ranking, topic grouping, neighbour links). Keeps source wording; it selects sentences, it does not rewrite them.
- `lib/gemini.dart`: direct call to Gemini `generateContent` with the user's keys. Key goes in the `x-goog-api-key` header, never the URL. Rotates to the next key on any failure, validates and clamps model output, and the app falls back to the local extractor on failure.
- `lib/settings.dart`: keys, "use Gemini" switch and consent flag in `flutter_secure_storage`, on the device only.
- `lib/board.dart`: card/link/shape models, `buildBoard` (notes to mind-map), `parseBoardJson` (sanitizing import), painter.
- `lib/main.dart`: UI and state.

## Trust and privacy
- Default path is offline for notes. Speech recognition uses the device or browser recognizer, which may send audio to its vendor. Say so; ask consent before recording others.
- Gemini is opt-in. First use asks before the transcript leaves the device. No key is bundled in the app or repo.
- Output is labelled "AI summary" or "Rule-based extract". Local notes never invent content. AI notes are told to use only the transcript, but they can still be wrong; the user edits and confirms.
- Guest-only: nothing persists except settings. Export board JSON to keep work.

## Not built
- Local/offline speech model (sherpa_onnx or Whisper) and an on-device LLM. Both were deliberately deferred.
- Accounts, sync, payments (the old RevenueCat test purchase was not ported).
- File download of exports (clipboard only), Excalidraw export.

## Verify before claiming
- Test live speech on the real phone and browser, including a long session and an interruption.
- Test the notes against real consented transcripts and count missed or false points.
- Test Gemini with your own key on device: success, bad key, rate limit, offline.
