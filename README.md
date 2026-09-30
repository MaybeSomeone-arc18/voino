# Voino

Turn words from meetings, lectures and discussions into editable notes and a visual board. Voino includes a browser prototype and a Capacitor Android app (`com.maybesomeone.voino`). The Android app uses native speech recognition and RevenueCat's Test Store. This is an unreleased Next Gen student prototype, not a production subscription service.

## What works and what does not

- Capture speech where the browser/device supports it. Type/paste remains available; on phones, keyboard dictation is an optional fallback if the keyboard provides it.
- Stop listening to create board cards automatically, or tap **Make editable board**. Correct the transcript first when needed. User-edited boards are not automatically replaced.
- Edit cards, change colors, add cards, connect cards, draw circles/boxes, export notes as text and the board as JSON. Phone cards stack for readability; desktop cards can be dragged.
- Notes are verbatim, rule-based extracts, not an AI summary. Shapes/connectors are manual, not inferred diagrams.
- Android offers a RevenueCat sandbox purchase demonstration with `voino_pro` entitlement. No real charge or actual subscription price is represented by this flow. Pro history/cloud sync is **not implemented**; purchasing does not save notes.
- Guest work is only in the current tab/app session. Export before reload/closing/reset. There is no cloud account, guaranteed offline launch, audio-file recorder, uploaded-audio transcription, or universal speech support.

## Browser setup

Use Node 22 or later and npm:

```bash
npm ci
npm test
npm run serve
```

Open `http://localhost:8080`. Browser source works without bundling; native SDK imports run only inside Capacitor. Browser speech support, permissions and online service availability vary. If the mic is unavailable, use the labeled manual path. Do not present typed input as speech recognition.

## Android debug setup

Install JDK 21, Android SDK platform 36 and compatible build tools. Set `JAVA_HOME` and `ANDROID_HOME` for your installation; accept Android SDK licenses. Android minimum SDK is defined in `android/variables.gradle`.

```bash
npm ci
npm test
node build.cjs
npx cap sync android
cd android
./gradlew assembleDebug
```

APK output: `android/app/build/outputs/apk/debug/app-debug.apk`. On Windows use `gradlew.bat`. Install only as a debug prototype; allow microphone permission and ensure an Android speech service is installed/enabled. Speech may require internet. Do not submit this debug/Test Store build to Google Play.

### RevenueCat public SDK key

`build.cjs` contains the public Test Store SDK identifier configured for this prototype, so the debug build has no placeholder key. It is a public client identifier, **not a secret RevenueCat API key**. You can override it for your own project:

```bash
REVENUECAT_KEY='your_public_test_store_sdk_key' node build.cjs
npx cap sync android
```

Your Test Store must have a current offering/package linked to the `voino_pro` entitlement. Sandbox entitlement access must include the test user. The configured project is a development service, whose availability is not guaranteed. Production builds require an explicit platform public SDK key and reject the default/Test Store key. A production key alone does not implement production billing or sync.

### Acceptance tests on the actual device

1. Speak: "Photosynthesis means plants use sunlight to make energy. Remember to submit the biology worksheet Friday." Stop. Check transcript, point and action cards, then edit a card.
2. Resume speech: old words remain. After editing a card, another stop must not replace it automatically. Explicit regeneration asks before replacing edited content.
3. Start speech and reset. No crash or stale words should return.
4. Tap **Test Pro (history unavailable)**. Check the Test Store offering modal, then test failure and cancel first: neither should activate `voino_pro`. Finally simulate success: verify sandbox entitlement/purchase status. All of these are test transactions, not real revenue.
5. Reopen promptly to test CustomerInfo entitlement readback. Test Store subscriptions expire rapidly (a monthly test subscription lasts about 25 minutes through renewals), so a later inactive result may be expected.
6. Confirm corresponding sandbox transaction in RevenueCat. Local tests use synthetic speech/SDK responses and do not replace these live acceptance tests.

## Privacy and licenses

Ask permission before capturing other people's speech. Browser/device recognition can send audio to its service provider; Voino has no own transcription backend. RevenueCat handles sandbox purchase/customer data. Never record private conversations or identifying information in a public submission video.

Project code is MIT licensed; see [LICENSE](LICENSE). Third-party dependencies and fonts retain their own licenses; preserve applicable notices. Optional Google Fonts may be fetched online, with local fallbacks if unavailable.

## Shipaton Next Gen

Intended entry: Next Gen only, using a public licensed repository plus device demo instead of a store release. This does not claim organizer approval or a completed Devpost submission. The owner must finish the qualifying academic-email/category fields, supply honest device footage and required images, review materials and submit before the official deadline.
