import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/auto_notes.dart';
import 'package:voino/main.dart' show notesActionLabel;

void main() {
  String words(int n) => List.generate(n, (i) => 'w$i').join(' ');

  group('AutoNotes', () {
    test('first refresh primes early, then throttles by words and time', () {
      var now = DateTime(2026, 1, 1, 12);
      final a = AutoNotes(now: () => now);
      expect(a.due(words(30)), isFalse);
      expect(a.due(words(70)), isTrue); // first prime at 60 words
      a.markRun(words(70));
      expect(a.due(words(100)), isFalse); // needs 100 NEW words
      now = now.add(const Duration(minutes: 2));
      expect(a.due(words(150)), isFalse); // only 80 new words
      expect(a.due(words(171)), isTrue);
      a.markRun(words(171));
      now = now.add(const Duration(minutes: 5));
      expect(a.due(words(400)), isTrue); // plenty new + interval passed
    });

    test('interval gate blocks rapid repeats', () {
      var now = DateTime(2026, 1, 1, 12);
      final a = AutoNotes(now: () => now);
      a.markRun(words(100));
      now = now.add(const Duration(seconds: 30));
      expect(a.due(words(500)), isFalse); // words ok, time not
    });

    test('reset reprimes', () {
      var now = DateTime(2026, 1, 1, 12);
      final a = AutoNotes(now: () => now);
      a.markRun(words(500));
      a.reset();
      now = now.add(const Duration(minutes: 10));
      expect(a.due(words(70)), isTrue);
    });
  });

  group('ListeningBanner', () {
    testWidgets('shows listening state and reports taps', (t) async {
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: ListeningBanner(onTap: () => taps++)),
      ));
      expect(find.textContaining('Listening'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      await t.tap(find.byType(ListeningBanner));
      expect(taps, 1);
    });
  });
}

void notesActionLabelTests() {
  group('notesActionLabel', () {
    test('lifecycle: Make board -> Notes up to date -> Update notes when stale', () {
      expect(notesActionLabel(busy: false, hasNotes: false, stale: false), 'Make board');
      expect(notesActionLabel(busy: false, hasNotes: true, stale: false), 'Notes up to date');
      expect(notesActionLabel(busy: false, hasNotes: true, stale: true), 'Update notes');
      expect(notesActionLabel(busy: true, hasNotes: true, stale: true), 'Working...');
    });
  });
  notesActionLabelTests();
}
