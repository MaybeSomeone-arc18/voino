# Voino

Turn words from meetings, lectures and discussions into editable notes and a visual board. Flutter app for Android and web (Vercel).

## What it does
- Capture speech, or type/paste. Android uses the device recognizer (`speech_to_text`). Web offers a toggle: **Whisper (local)** runs whisper-tiny.en in the browser (about 40 MB, downloaded on first use and cached, nothing sent to a server), or **Device speech**. Whisper is the default when the browser has no speech recognizer. Device/browser recognizers may use an online vendor service.
- **Local notes by default:** filler removal, keyword-ranked points, topic grouping, action items. No network, no key.
- **Optional Gemini summaries:** tap the settings icon and add your own API key(s), one per line. Keys stay on the device (secure storage) and go only to Google; the app rotates through them and falls back to local notes on failure. The transcript is sent to Google only after you confirm.
- **Visual board:** notes become a mind-map with a title card, boxed topic columns, a To-do column, labelled arrows and a circle on the key point. Drag, edit, recolor, delete, connect cards, draw circles and boxes.
- **Share and edit:** copy the board JSON; anyone can paste it into Import board JSON to open and edit it.
- **Clear all** wipes the transcript, notes, board and recording in one tap.
- Guest-only: nothing but settings is stored. Copy your notes or board JSON before closing.

Not built: on-device speech model or LLM, accounts/sync, payments, file download.

## Run
```bash
flutter pub get
flutter test
flutter run -d chrome        # web
flutter run                  # Android device
flutter build apk --debug
flutter build web --release  # output: build/web
```

Vercel builds Flutter from `vercel.json` (clones stable Flutter, then `flutter build web`).

Ask permission before recording other people. MIT licensed, see [LICENSE](LICENSE).
