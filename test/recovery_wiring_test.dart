import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voino/logic.dart';

// Cross-language contract test: the fixture is a REAL payload produced by
// web/whisper.js stop() in the Node wiring test (tools/recovery_wiring_test.js),
// consumed here by the REAL Dart handler (recoveryRewrite, the function the
// onRecover callback invokes).

Map<String, dynamic> loadFixture() {
  final f = File('tools/fixtures/recovery_payload.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final fx = loadFixture();
  final transcript = fx['transcript'] as String;
  final payload = fx['payload'] as String;

  test('real JS payload rewrites its gap marker through the real handler', () {
    final out = recoveryRewrite(
      transcript,
      payload,
      currentSid: 1,
      revAtCaptureStart: 5,
      currentUserRev: 5,
    );
    expect(out, isNotNull);
    expect(out!.contains('[gap '), isFalse);
    expect(out.length, greaterThan(transcript.length));
  });

  test('same payload, stale session (capture moved on): rejected', () {
    expect(
      recoveryRewrite(transcript, payload, currentSid: 2, revAtCaptureStart: 5, currentUserRev: 5),
      isNull,
    );
  });

  test('same payload, user edit during capture or drain: rejected', () {
    expect(
      recoveryRewrite(transcript, payload, currentSid: 1, revAtCaptureStart: 5, currentUserRev: 6),
      isNull,
    );
  });

  test('same payload, Clear or new draft then identical text reinserted: rejected', () {
    // The revision has advanced even though the document looks the same.
    expect(
      recoveryRewrite(transcript, payload, currentSid: 1, revAtCaptureStart: 0, currentUserRev: 1),
      isNull,
    );
  });

  test('same payload, prior-session identical marker present: marker skipped', () {
    final withOld = 'older note [gap 0:00-0:24 not transcribed] $transcript';
    expect(
      recoveryRewrite(withOld, payload, currentSid: 1, revAtCaptureStart: 5, currentUserRev: 5),
      isNull, // applyGapRecoveries skips the string (count 2 != total 1); no change => null
    );
    expect(
      applyGapRecoveries(withOld, [
        {'str': '[gap 0:00-0:24 not transcribed]', 'nth': 0, 'total': 1, 'repl': 'X'}
      ]),
      withOld,
    );
  });

  test('malformed payload: rejected', () {
    expect(
      recoveryRewrite(transcript, 'not json', currentSid: 1, revAtCaptureStart: 5, currentUserRev: 5),
      isNull,
    );
  });
}
