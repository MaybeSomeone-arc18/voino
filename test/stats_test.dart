import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voino/stats.dart';

void main() {
  Map<String, String> store() => <String, String>{};

  Stats make(
    Map<String, String> mem,
    List<String> hits, {
    DateTime? day,
    bool fail = false,
  }) {
    final client = MockClient((req) async {
      if (fail) throw Exception('offline');
      hits.add((req as http.Request).body);
      return http.Response('{}', 200);
    });
    return Stats(
      client: client,
      read: (k) async => mem[k],
      write: (k, v) async => mem[k] = v,
      projectId: 'voinoo',
      apiKey: 'test-key',
      now: day != null ? () => day : null,
    );
  }

  Map<String, dynamic> lastBody(List<String> hits) =>
      jsonDecode(hits.last) as Map<String, dynamic>;

  test('disabled without an API key: no network call', () async {
    final hits = <String>[];
    final s = Stats(
      client: MockClient((req) async => throw StateError('must not post')),
      read: (k) async => null,
      write: (k, v) async {},
      apiKey: '',
    );
    await s.appOpened();
    await s.sessionStarted();
    await s.boardCreated();
    expect(hits, isEmpty);
    expect(s.enabled, isFalse);
  });

  test('appOpened counts the device once per UTC day', () async {
    final mem = store();
    final hits = <String>[];
    final s = make(mem, hits, day: DateTime.utc(2026, 10, 26, 5));
    await s.appOpened();
    await s.appOpened(); // same day: no second count
    expect(hits, hasLength(1));
    final body = lastBody(hits);
    final transforms = body['writes'][0]['transform']['fieldTransforms'] as List;
    final paths = {
      for (final t in transforms) t['fieldPath']: t['increment']['integerValue'],
    };
    expect(paths, {'devices': '1'}); // first day: not "returning"
    expect((body['writes'] as List), hasLength(2)); // all + daily doc
    expect(
      body['writes'][1]['transform']['document'] as String,
      endsWith('counters/daily_2026-10-26'),
    );
  });

  test('a device first seen on an earlier day counts as returning', () async {
    final mem = store()..['stats_device_id'] = 'abc'..['stats_first_day'] = '2026-10-25';
    final hits = <String>[];
    final s = make(mem, hits, day: DateTime.utc(2026, 10, 26));
    await s.appOpened();
    final body = lastBody(hits);
    final transforms = body['writes'][0]['transform']['fieldTransforms'] as List;
    final paths = {
      for (final t in transforms) t['fieldPath']: t['increment']['integerValue'],
    };
    expect(paths, {'devices': '1', 'returning': '1'});
  });

  test('session and board increments carry only counts, no identity', () async {
    final mem = store();
    final hits = <String>[];
    final s = make(mem, hits);
    await s.sessionStarted();
    await s.boardCreated();
    expect(hits, hasLength(2));
    final raw = hits.first;
    expect(raw, contains('"sessions"'));
    expect(raw, isNot(contains('stats_device_id')));
    expect(raw, isNot(contains(mem['stats_device_id'] ?? 'no-id')));
    final body2 = lastBody(hits);
    expect(
      jsonEncode(body2),
      contains('"fieldPath":"boards"'),
    );
  });

  test('network failure is swallowed', () async {
    final mem = store();
    final hits = <String>[];
    final s = make(mem, hits, fail: true);
    await s.sessionStarted(); // must not throw
    await s.appOpened();
  });
}
