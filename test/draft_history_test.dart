import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/draft_history.dart';

void main() {
  Map<String, dynamic> draft(String t) => {
        'title': t,
        'transcript': 'some words about $t',
        'summary': 'summary of $t',
      };

  (DraftHistory, Map<String, String>) makeStore([String? initial]) {
    final store = <String, String>{if (initial != null) 'voino_history_v1': initial};
    final h = DraftHistory(
      read: () async => store['voino_history_v1'],
      write: (s) async => store['voino_history_v1'] = s,
    );
    return (h, store);
  }

  test('starts empty and ready with no stored history (migration-safe)', () async {
    final (h, _) = makeStore();
    await h.load();
    expect(h.ready, isTrue);
    expect(h.entries, isEmpty);
    expect(h.error, isEmpty);
  });

  test('archive keeps content, newest first; empty drafts are not archived', () async {
    final (h, _) = makeStore();
    await h.load();
    expect(await h.archive({'title': '', 'transcript': '', 'summary': ''}), isFalse);
    expect(await h.archive(draft('first')), isTrue);
    expect(await h.archive(draft('second')), isTrue);
    expect(h.entries.map((e) => e.title), ['second', 'first']);
  });

  test('cap of 5 drops the OLDEST entry when full', () async {
    final (h, _) = makeStore();
    await h.load();
    for (var i = 1; i <= 6; i++) {
      await h.archive(draft('note $i'));
    }
    expect(h.entries, hasLength(5));
    expect(h.entries.first.title, 'note 6');
    expect(h.entries.last.title, 'note 2');
    expect(h.entries.any((e) => e.title == 'note 1'), isFalse);
  });

  test('delete removes exactly one entry and persists', () async {
    final (h, store) = makeStore();
    await h.load();
    await h.archive(draft('keep'));
    await h.archive(draft('drop'));
    await h.remove(h.entries.firstWhere((e) => e.title == 'drop').id);
    expect(h.entries.map((e) => e.title), ['keep']);
    final persisted = jsonDecode(store['voino_history_v1']!) as List;
    expect(persisted, hasLength(1));
    expect(persisted.single['title'], 'keep');
  });

  test('archived draft round-trips with its full payload', () async {
    final (h, _) = makeStore();
    await h.load();
    final d = draft('round trip')..['lastSource'] = 'some words about round trip';
    await h.archive(d);
    expect(h.entries.single.draft['summary'], 'summary of round trip');
    expect(h.entries.single.draft['lastSource'], 'some words about round trip');
  });

  test('corrupt history never blocks: loads empty with a readable error', () async {
    final (h, _) = makeStore('{"not":"a list"}');
    await h.load();
    expect(h.ready, isTrue);
    expect(h.entries, isEmpty);
    expect(h.error, isNotEmpty);
  });

  test('malformed entries inside the list are skipped, valid ones kept', () async {
    final good = {'id': 'a', 'title': 'good', 'savedAt': 'x', 'draft': draft('good')};
    final (h, _) = makeStore(jsonEncode([good, {'broken': true}, 42]));
    await h.load();
    expect(h.entries, hasLength(1));
    expect(h.entries.single.title, 'good');
    expect(h.error, isEmpty);
  });
}
