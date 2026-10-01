import 'package:flutter_test/flutter_test.dart';
import 'package:voino/listening_session.dart';

void main() {
  testWidgets('normal timeout restarts and keeps user intent', (t) async {
    var starts = 0;
    late ListeningSession s;
    s = ListeningSession(
      startEngine: (_) async {
        starts++;
        s.status('listening');
      },
      stopEngine: () async {},
      onWords: (_, _) {},
    );
    await s.start();
    expect(s.active, true);
    s.status('notListening');
    s.status('done');
    expect(s.requested, true);
    expect(s.active, false);
    expect(s.message, contains('Reconnecting'));
    await t.pump(const Duration(milliseconds: 1000));
    expect(starts, 2);
    expect(s.active, true);
    await s.stop();
    s.dispose();
  });
  testWidgets('Stop during restart cancels future sessions', (t) async {
    var starts = 0;
    late ListeningSession s;
    s = ListeningSession(
      startEngine: (_) async {
        starts++;
        s.status('listening');
      },
      stopEngine: () async {},
      onWords: (_, _) {},
    );
    await s.start();
    s.status('done');
    await s.stop();
    await t.pump(const Duration(seconds: 2));
    expect(starts, 1);
    expect(s.requested, false);
    expect(s.active, false);
    s.dispose();
  });
  testWidgets('silence is recoverable but network error stops intent', (
    t,
  ) async {
    var starts = 0;
    late ListeningSession s;
    s = ListeningSession(
      startEngine: (_) async {
        starts++;
        s.status('listening');
      },
      stopEngine: () async {},
      onWords: (_, _) {},
    );
    await s.start();
    s.error('error_speech_timeout');
    await t.pump(const Duration(seconds: 1));
    expect(starts, 2);
    s.error('error_network');
    s.status('done');
    await t.pump(const Duration(seconds: 2));
    expect(starts, 2);
    expect(s.requested, false);
    expect(s.message, contains('error_network'));
    s.dispose();
  });
  testWidgets(
    'late results from old recognizer cannot overwrite next session',
    (t) async {
      final callbacks = <void Function(String)>[];
      final seen = <String>[];
      late ListeningSession s;
      s = ListeningSession(
        startEngine: (cb) async {
          callbacks.add(cb);
          s.status('listening');
        },
        stopEngine: () async {},
        onWords: (w, _) => seen.add(w),
      );
      await s.start();
      callbacks.first('First words');
      s.status('done');
      await t.pump(const Duration(seconds: 1));
      callbacks.first('Stale');
      callbacks.last('New words');
      expect(seen, ['First words', 'New words']);
      await s.stop();
      s.dispose();
    },
  );
  testWidgets('failed starts are bounded rather than infinite', (t) async {
    var starts = 0;
    final s = ListeningSession(
      startEngine: (_) async {
        starts++;
        throw Exception();
      },
      stopEngine: () async {},
      onWords: (_, _) {},
    );
    await s.start();
    await t.pump(const Duration(seconds: 1));
    expect(starts, 2);
    expect(s.requested, false);
    await t.pump(const Duration(seconds: 5));
    expect(starts, 2);
    s.dispose();
  });
  testWidgets('silent start failure never shows a live mic forever', (t) async {
    final s = ListeningSession(
      startEngine: (_) async {},
      stopEngine: () async {},
      onWords: (_, _) {},
    );
    await s.start();
    expect(s.active, false);
    await t.pump(const Duration(seconds: 4));
    expect(s.requested, false);
    expect(s.message, contains('microphone_unavailable'));
    s.dispose();
  });
  testWidgets('background stop preserves transcript and does not auto resume', (
    t,
  ) async {
    var words = '';
    late ListeningSession s;
    s = ListeningSession(
      startEngine: (cb) async {
        s.status('listening');
        cb('Keep these words');
      },
      stopEngine: () async {},
      onWords: (w, _) => words = w,
    );
    await s.start();
    await s.stop(note: 'Paused in background. Tap to resume.');
    s.status('done');
    await t.pump(const Duration(seconds: 2));
    expect(words, 'Keep these words');
    expect(s.requested, false);
    expect(s.message, contains('Paused'));
    s.dispose();
  });
}
