# Voino

Listen during a meeting, lecture or discussion, then turn the transcript into editable notes and a visual board. This is a small, browser-first hackathon prototype: live speech recognition where supported, manual transcript input, deterministic extraction of key points and explicit to-dos, and ephemeral guest sessions. It does **not** record an audio file or transcribe uploaded files. It does **not** run offline, promise complete transcripts, generate AI summaries, or have a RevenueCat paywall.

## Run

```bash
npm test
npm run serve
```

Open http://localhost:8080 in desktop Chrome. Allow the microphone. Speak for a few seconds, press Stop, correct the transcript if needed, then press Turn into notes. Speech recognition is a browser feature whose availability and remote processing vary; paste/type a transcript if it is unavailable. No transcript is sent to Voino's own server. Browser speech recognition may send audio to the browser vendor. Guest drafts are not stored by Voino and vanish on reload or a fresh recording. Download to keep them. Get consent before recording anyone else's voice.

## Demo script

1. Name a note "Study group". Say: "Photosynthesis means plants use sunlight to make energy. Remember to submit the biology worksheet Friday." Stop.
2. Correct any transcription error. Generate notes, inspect that the first sentence is a key point and the second is a to-do.
3. Edit a line; download the text and board before leaving. Refresh to show the guest session is empty.

Never use a typed transcript as if it was speech recognition during a demo. The live mic and typed-input routes must be identified honestly. This is not a native mobile app or an eligible global Shipaton entry yet.

## Visual board

Generated key points and explicit next steps appear as cards on a dot-grid canvas. Each card is editable; its handle supports pointer drag and arrow-key movement. Add an idea card manually, or save the board as a JSON file. Card positions and content persist only while this tab stays open in guest mode. Voino does not claim to understand the full discussion, summarize it with AI, or produce Excalidraw diagrams, mind maps, or automatic graphics. The board is a simple editable visual workspace.

## Personalization and offline boundary

On desktop, change a card's color using ◐, connect two cards by clicking Connect two cards then each card, and arrange cards via handle drag or arrow keys. Cards, colors and connectors stay in the current guest tab and are included in the JSON export. The note editor and visual board need no network after the page loads. Speech recognition needs the browser's supported service and may need internet. This version has no service worker, so it is not guaranteed to reopen offline; keep the loaded tab open when demonstrating without Wi-Fi. On narrow phones, cards stack for readability and connector arrows remain visible between them.

## Sketchboard look

The board has a hand-drawn-inspired CSS style, sketchy arrows and handwriting-style lettering. It is not Excalidraw or an Excalidraw file format. Cards, colors, arrows and edits are Voino features under that skin; guest work is not saved. If the remote display font does not load offline, the browser uses a local cursive fallback; the board remains functional.

## Phone-first prototype and device needs

Open this web app in a recent Chrome browser on a phone or desktop. The board, notes, colors, arrows, circles and boxes are browser UI and have no downloaded model or paid API. Browser microphone speech recognition support and service availability vary by device, browser, permissions and connection; manual transcript entry is always available. For the live demo, test Chrome speech recognition on the actual phone first. A typed/pasted transcript is the honest fallback if it fails. There is no guarantee of a particular minimum phone RAM, storage quota or operating system version until real-device tests. The source web assets are small (roughly 40 KB of HTML/CSS/JavaScript before transfer compression and excluding optional web fonts), but the browser's speech service may use network data. Guest notes vanish on reload or a fresh Start; export important notes to a file.

Circles and boxes are manual drawing tools on the board, not graphs inferred from speech. Choose a tool and drag on blank canvas. Undo removes the last drawn shape. On phones, cards stack and their existing arrow connectors remain visible. This is a browser prototype, not a native mobile app; no AI model is downloaded. Chrome's desktop built-in Summarizer API is not available on Android Chrome today, so no no-cost on-phone AI summary is promised. Source: https://developer.chrome.com/docs/ai/summarizer-api .
