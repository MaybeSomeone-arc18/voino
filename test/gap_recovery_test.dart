import 'package:flutter_test/flutter_test.dart';
import 'package:voino/logic.dart';

Map<String, dynamic> op(String str, int nth, int total, String repl) =>
    {'str': str, 'nth': nth, 'total': total, 'repl': repl};

const m = '[gap 0:00-0:02 not transcribed]';

void main() {
  test('basic single rewrite', () {
    expect(
      applyGapRecoveries('a $m c', [op(m, 0, 1, 'hello')]),
      'a hello c',
    );
  });

  test('several identical markers each rewrite to their own text', () {
    // The bug this guards: a second rewrite must not fail because the first
    // one already changed the transcript's occurrence count.
    expect(
      applyGapRecoveries('a $m b $m c', [op(m, 0, 2, 'X'), op(m, 1, 2, 'Y')]),
      'a X b Y c',
    );
  });

  test('replacement containing its own marker string works', () {
    expect(
      applyGapRecoveries('a $m c', [op(m, 0, 1, 'X $m Y')]),
      'a X $m Y c',
    );
  });

  test('user-duplicated marker count fails safe: no rewrite', () {
    final t = 'a $m b $m c $m';
    expect(
      applyGapRecoveries(t, [op(m, 0, 2, 'X'), op(m, 1, 2, 'Y')]),
      t,
    );
  });

  test('user-deleted marker fails safe: no rewrite', () {
    final t = 'a $m c';
    expect(
      applyGapRecoveries(t, [op(m, 0, 2, 'X'), op(m, 1, 2, 'Y')]),
      t,
    );
  });

  test('edited marker text is simply not found: no rewrite', () {
    final t = 'a [gap 0:00-0:02 not transcribed.] c';
    expect(applyGapRecoveries(t, [op(m, 0, 1, 'X')]), t);
  });

  test('different marker strings rewrite independently', () {
    const m2 = '[gap 0:02-0:04 not transcribed]';
    expect(
      applyGapRecoveries('a $m b $m2 c', [op(m, 0, 1, 'X'), op(m2, 0, 1, 'Y')]),
      'a X b Y c',
    );
  });

  test('empty ops leave the transcript unchanged', () {
    expect(applyGapRecoveries('a $m c', const []), 'a $m c');
  });

  test('prior-session identical marker fails closed: no rewrite', () {
    // The same note can hold a marker from an earlier capture with identical
    // text (each capture restarts its clock). Occurrence count (2) no longer
    // matches this capture's emitted total (1), so identity is uncertain and
    // nothing is rewritten.
    final t = 'old $m middle new $m end';
    expect(applyGapRecoveries(t, [op(m, 0, 1, 'X')]), t);
  });

  group('recoveryAllowed gate', () {
    test('same capture, untouched transcript: allowed', () {
      expect(
        recoveryAllowed(payloadSid: 3, currentSid: 3, revAtCaptureStart: 7, currentUserRev: 7),
        isTrue,
      );
    });

    test('stale callback from an older capture: rejected', () {
      expect(
        recoveryAllowed(payloadSid: 2, currentSid: 3, revAtCaptureStart: 7, currentUserRev: 7),
        isFalse,
      );
    });

    test('user typed during capture (same-count edit or reorder): rejected', () {
      expect(
        recoveryAllowed(payloadSid: 3, currentSid: 3, revAtCaptureStart: 7, currentUserRev: 8),
        isFalse,
      );
    });

    test('Clear or new draft during the drain: rejected', () {
      // Clear/new draft bump transcriptUserRev; even if the user re-inserts
      // identical text, the revision no longer matches.
      expect(
        recoveryAllowed(payloadSid: 3, currentSid: 3, revAtCaptureStart: 0, currentUserRev: 1),
        isFalse,
      );
    });

    test('new capture started before the old drain finished: rejected', () {
      // Both counters increment per start, so the old payload's sid is behind.
      expect(
        recoveryAllowed(payloadSid: 3, currentSid: 4, revAtCaptureStart: 7, currentUserRev: 7),
        isFalse,
      );
    });
  });
}
