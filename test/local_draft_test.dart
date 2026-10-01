import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/local_draft.dart';

Map<String, dynamic> data(String transcript) => {
  'title': 'Lecture',
  'transcript': transcript,
  'summary': 'Summary',
  'source': 'Rule-based extract',
  'cards': [],
  'connections': [],
  'shapes': [],
};
void main() {
  testWidgets('debounces words and restores a whole draft', (t) async {
    String? raw;
    final draft = LocalDraft(
      read: () async => raw,
      write: (s) async => raw = s,
    );
    await draft.load();
    draft.changed(data('first'));
    draft.changed(data('final'));
    await t.pump(const Duration(milliseconds: 600));
    expect(jsonDecode(raw!)['transcript'], 'final');
    expect(draft.saved, true);
    final next = LocalDraft(read: () async => raw, write: (_) async {});
    final restored = await next.load();
    expect(restored!['summary'], 'Summary');
    expect(restored['title'], 'Lecture');
    draft.dispose();
    next.dispose();
  });
  test('read failure does not overwrite unseen work', () async {
    var writes = 0;
    final draft = LocalDraft(
      read: () async => throw Exception(),
      write: (_) async {
        writes++;
      },
    );
    expect(await draft.load(), isNull);
    draft.changed(data('new'));
    await draft.flush();
    expect(writes, 0);
    expect(draft.ready, false);
    expect(draft.error, contains('could not be read'));
    draft.dispose();
  });
  test('malformed draft is retained rather than overwritten', () async {
    var writes = 0;
    final draft = LocalDraft(
      read: () async => '{broken',
      write: (_) async {
        writes++;
      },
    );
    await draft.load();
    draft.changed(data('new'));
    await draft.flush();
    expect(writes, 0);
    expect(draft.error, isNotEmpty);
    draft.dispose();
  });
  test('write failure is visible and explicit flush retries', () async {
    var fail = true;
    String? raw;
    final draft = LocalDraft(
      read: () async => null,
      write: (s) async {
        if (fail) throw Exception();
        raw = s;
      },
    );
    await draft.load();
    draft.changed(data('keep me'));
    await draft.flush();
    expect(draft.saved, false);
    expect(draft.error, contains('failed'));
    fail = false;
    await draft.flush();
    expect(jsonDecode(raw!)['transcript'], 'keep me');
    expect(draft.saved, true);
    draft.dispose();
  });
  test('serialized writes cannot let an older draft win', () async {
    final hold = Completer<void>();
    final seen = <String>[];
    var calls = 0;
    final draft = LocalDraft(
      read: () async => null,
      write: (s) async {
        calls++;
        if (calls == 1) await hold.future;
        seen.add(jsonDecode(s)['transcript']);
      },
    );
    await draft.load();
    draft.changed(data('old'));
    final first = draft.flush();
    await Future<void>.delayed(Duration.zero);
    draft.changed(data('new'));
    final second = draft.flush();
    hold.complete();
    await first;
    await second;
    expect(seen, ['old', 'new']);
    expect(draft.saved, true);
    draft.dispose();
  });
  test('clear persists an empty draft', () async {
    String? raw;
    final draft = LocalDraft(
      read: () async => null,
      write: (s) async => raw = s,
    );
    await draft.load();
    draft.changed(data('old'));
    await draft.flush();
    draft.changed({...data(''), 'title': '', 'summary': ''});
    await draft.flush();
    expect(jsonDecode(raw!)['transcript'], '');
    expect(jsonDecode(raw!)['cards'], isEmpty);
    draft.dispose();
  });
}
