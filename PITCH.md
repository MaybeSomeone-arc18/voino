# Voino pitch and demo plan (local Shipaton, Wednesday morning)

## One-line promise

"Voino listens to meetings and lectures, then turns the transcript into editable notes."

## Three-minute pitch

**0:00-0:25 - Everyday problem.** "In a lecture or meeting, we want to listen, not spend the whole time typing. But afterward, our next steps are buried in a long discussion."

**0:25-0:50 - What Voino does, honestly.** "I open Voino during the discussion. Chrome transcribes the speech it hears in real time. I review any misheard words, then turn that transcript into editable key points and explicit next steps. This prototype extracts sentences; it does not yet write a full AI summary."

**0:50-1:50 - Real demo.** Use desktop Chrome and a prepared, consented 15-second speech: "Our presentation is Wednesday. The key point is that our pilot saved each team an hour. Remember to send the final slides tonight. We need to review the demo tomorrow." Show the live transcript, fix any error, click Turn into notes, then scroll to the board. Drag a next-step card beside a key point, change its color, and connect them with an arrow. Edit a card to clarify its wording. Reload only after exporting, to show a new guest session starts empty. If the microphone or network fails, say that and type the same words in the manual transcript field. Never imply typed input was recognized speech.

**1:50-2:30 - Product choices.** "The output is not a wall of text. It's a board I can arrange, edit and save in this browser. Each generated card comes directly from the transcript. I can download the text and the board. No account is needed for this prototype."

**2:30-3:00 - Honest boundary and next step.** "Today, it uses Chrome's speech recognition, which may rely on the browser's online speech service. It's not fully local-first yet and doesn't identify speakers or infer who owns a task. The headline next step is on-device transcription for zero-latency, fully offline listening. Later: consent-aware speaker assignment."

## Backups

1. Pre-test mic permission, Chrome and internet on the exact demo laptop Tuesday night and Wednesday morning.
2. Prepare a sample transcript in a local text file, **clearly label the fallback as typed/pasted**.
3. Record a real screen capture only after a successful mic test, then keep it locally for a live-demo failure.
4. Prepare the tested demo transcript or export; bring the ZIP and a local server method (`python3 -m http.server 8080`) in case hosted deployment is unavailable. For local mic access, `http://localhost` is generally a secure context, but test on the actual computer.
5. Confirm the organizer's actual date, venue, format and judging rule directly; the forwarded event update said September 30 was only likely.

## Do not claim

No native mobile app, offline transcription, audio file recording, upload/transcription, speaker recognition, AI-generated diagram, actual Excalidraw compatibility, native RevenueCat payment, or global Devpost eligibility.

## No-wifi scenario

Once the page is already loaded, the editor, deterministic note extraction, visual board, card colors and connectors, in-tab edits, and text/JSON export work without a network. Browser speech recognition does not: if wifi fails, show a clearly labeled typed/pasted transcript, generate and customize the same cards, and avoid saying Voino "listened" in that fallback. A full page reload while offline may fail without a service worker or prior browser cache; keep the page open for the demo. The future vision is on-device transcription for zero-latency, fully offline listening.

## Style claim

Call this an "Excalidraw-style" or "hand-drawn-inspired" board. It is Voino's own small card canvas, not embedded Excalidraw and not compatible with Excalidraw files. The cosmetic sketch font may load online, with local cursive fallback offline. In the live demo, drag a card, change its color and connect two cards with a sketchy arrow.

## Phone-first demo variant

Open the hosted site in Chrome on the actual phone before the pitch. Check microphone permission, browser speech support and connectivity. Speak one prepared line in a quiet place; show the transcript, correct a word, generate cards, tap two cards to connect them. Draw a circle around a key point or box a next step by choosing the shape tool and dragging on blank canvas. Recolor a card, add a note, and export. If phone speech recognition is absent or unreliable, say "the mic service isn't available on this phone/network, so here's a labeled typed transcript; the notes and board still work." Do not claim on-phone audio always works. If no reliable hosted URL is available, bring a locally served desktop demo and describe phone support as unverified.

## Mainstream / cost story

No bundled AI model or API meter in this prototype: sentence extraction is rules-based JavaScript; the board is HTML/CSS/SVG. The source assets are roughly 40 KB before transfer compression, excluding fonts. Speech recognition may depend on Chrome's online service and phone/browser support; guest sessions do not persist, and network use may vary. Do not promise every phone or "unlimited AI". Google's Chrome Summarizer API currently does not support Android Chrome, so true on-device AI summaries require a different future implementation and testing, not a toggle waiting to be switched on. A future native model has separate storage/RAM/performance costs. Manual circles/boxes are built; automatic charts from data are roadmap only. Source: https://developer.chrome.com/docs/ai/summarizer-api .

## Product-positioning boundary

Sanskar wants Voino to eventually give an editable summary of the entire meeting, lecture or discussion. That is the product direction, not a claim about this prototype. Today Chrome transcribes speech where supported and simple rules extract verbatim key points and explicit to-dos, with a visual editing board. It can miss context and cannot guarantee completeness. Do not describe the output as an AI summary or a faithful summary of an entire session. The next product milestone is tested summarization with source links, with a viable cost/privacy path; on-device transcription remains the separate zero-latency/offline goal.
