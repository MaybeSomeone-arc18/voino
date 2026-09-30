import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voino/board.dart';
import 'package:voino/gemini.dart';
import 'package:voino/logic.dart';

const lecture = 'Um so photosynthesis means plants use sunlight to make energy. '
    'Photosynthesis happens in the chloroplast of plant cells. '
    'Chlorophyll absorbs sunlight and starts photosynthesis. '
    'The weather was nice. '
    'Remember to submit the biology worksheet Friday.';

void main() {
  group('speech', () {
    test('stitchSpeech dedupes cumulative and overlapping results', () {
      expect(stitchSpeech('hello', 'hello world'), 'hello world');
      expect(stitchSpeech('hello world', 'world again'), 'hello world again');
      expect(stitchSpeech('a b', 'c d'), 'a b c d');
      expect(stitchSpeech('', ' x  y '), 'x y');
    });
  });

  group('whisper chunk merge', () {
    test('cleanWhisperText strips non-speech tags', () {
      expect(cleanWhisperText(' [BLANK_AUDIO] '), '');
      expect(cleanWhisperText('Hello (music) there [ Silence ]'), 'Hello there');
      expect(cleanWhisperText('♪ la la ♪'), 'la la');
      expect(cleanWhisperText(null), '');
    });
    test('successive 5-second chunks append and dedupe overlap', () {
      var t = '';
      for (final chunk in ['Plants use sunlight', 'sunlight to make energy.', '[BLANK_AUDIO]', 'Chlorophyll absorbs light.']) {
        final c = cleanWhisperText(chunk);
        if (c.isNotEmpty) t = stitchSpeech(t, c);
      }
      expect(t, 'Plants use sunlight to make energy. Chlorophyll absorbs light.');
    });
  });

  group('local notes', () {
    test('separates actions, strips filler, keeps source wording', () {
      final n = makeNotes(lecture);
      expect(n.actions, ['Remember to submit the biology worksheet Friday.']);
      expect(n.points.first, startsWith('Photosynthesis means'));
      expect(n.source, 'rule');
    });
    test('groups related points into a topic and picks a key point', () {
      final n = makeNotes(lecture);
      expect(n.topics.any((t) => t.name == 'Photosynthesis' && t.points.length >= 2), isTrue);
      expect(n.keyPoint, isNotNull);
      expect(n.links, isNotEmpty);
    });
    test('empty transcript gives empty notes', () {
      final n = makeNotes('');
      expect(n.points, isEmpty);
      expect(n.topics, isEmpty);
    });
    test('long transcripts are trimmed to at most 8 points', () {
      final t = List.generate(30, (i) => 'Topic number $i explains item$i clearly.').join(' ');
      expect(makeNotes(t).points.length, lessThanOrEqualTo(8));
    });
  });

  group('gemini', () {
    Map<String, dynamic> goodJson() => {
          'title': 'Bio',
          'summary': 'Plants make energy.',
          'points': ['A.', 'B.', 'C.'],
          'actions': ['Submit worksheet'],
          'topics': [
            {'name': 'Plants', 'points': [0, 1, 9]},
          ],
          'links': [
            {'from': 0, 'to': 1, 'label': 'leads to'},
            {'from': 0, 'to': 7, 'label': 'bad'},
            {'from': 2, 'to': 2, 'label': 'self'},
          ],
          'keyPoint': 1,
        };
    String okBody() => jsonEncode({
          'candidates': [
            {'content': {'parts': [{'text': jsonEncode(goodJson())}]}}
          ]
        });

    test('validation drops bad indexes and puts unassigned points in Other', () {
      final n = noteFromGeminiJson(goodJson(), 'src', 'New note');
      expect(n.source, 'ai');
      expect(n.title, 'Bio');
      expect(n.topics.first.points, [0, 1]);
      expect(n.topics.last.name, 'Other');
      expect(n.topics.last.points, [2]);
      expect(n.links.length, 1);
      expect(n.keyPoint, 1);
    });

    test('rotates to the next key when one fails', () async {
      final seen = <String>[];
      final client = MockClient((req) async {
        seen.add(req.headers['x-goog-api-key']!);
        return seen.length == 1 ? http.Response('quota', 429) : http.Response(okBody(), 200);
      });
      final n = await GeminiClient(['k1', 'k2'], client: client).summarize('hello world');
      expect(seen, ['k1', 'k2']);
      expect(n.points.length, 3);
    });

    test('throws after every key fails, and never puts the key in the URL', () async {
      final urls = <String>[];
      final client = MockClient((req) async {
        urls.add(req.url.toString());
        return http.Response('no', 500);
      });
      await expectLater(GeminiClient(['k1', 'k2'], client: client).summarize('x'), throwsA(isA<GeminiException>()));
      expect(urls.every((u) => !u.contains('k1') && !u.contains('k2')), isTrue);
    });

    test('no keys throws immediately', () async {
      await expectLater(GeminiClient([' ', ''], client: MockClient((_) async => http.Response('', 200))).summarize('x'),
          throwsA(isA<GeminiException>()));
    });
  });

  group('board', () {
    test('buildBoard makes title, topic boxes, to-do column, arrows and key circle', () {
      final b = buildBoard(makeNotes(lecture, 'Bio'));
      expect(b.cards.first.type, 'title');
      expect(b.cards.where((c) => c.type == 'action').length, 1);
      expect(b.shapes.where((s) => s.type == 'box').length, greaterThanOrEqualTo(2));
      expect(b.shapes.where((s) => s.type == 'circle').length, 1);
      expect(b.links.any((l) => l.from == 'title'), isTrue);
      final ids = b.cards.map((c) => c.id).toSet();
      expect(b.links.every((l) => ids.contains(l.from) && ids.contains(l.to)), isTrue);
      expect(ids.length, b.cards.length);
    });

    test('board JSON round-trips and is sanitized on import', () {
      final b = buildBoard(makeNotes(lecture, 'Bio'));
      final raw = jsonEncode({
        'title': 'Bio',
        'transcript': 't',
        'cards': b.cards.map((c) => c.toJson()).toList(),
        'connections': b.links.map((l) => l.toJson()).toList(),
        'shapes': b.shapes.map((s) => s.toJson()).toList(),
      });
      final r = parseBoardJson(raw)!;
      expect(r.board.cards.length, b.cards.length);
      expect(r.board.links.length, b.links.length);
      expect(r.board.shapes.length, b.shapes.length);

      final evil = parseBoardJson(jsonEncode({
        'cards': [
          {'id': 'a', 'type': 'point', 'text': 'x', 'x': 99999, 'y': -5, 'color': 'red'},
          {'id': 'b', 'type': 'bogus', 'text': 'y'},
        ],
        'connections': [
          {'from': 'a', 'to': 'zzz'}
        ],
      }))!;
      expect(evil.board.cards.length, 1);
      expect(evil.board.cards.first.x, 4000);
      expect(evil.board.cards.first.y, 0);
      expect(evil.board.cards.first.color, 'mint');
      expect(evil.board.links, isEmpty);
    });

    test('invalid JSON is rejected', () {
      expect(parseBoardJson('not json'), isNull);
      expect(parseBoardJson('{"x":1}'), isNull);
    });
  });

  group('hosted summarizer and fallback', () {
    final url = Uri.parse('https://example.test/api/summarize');
    final serverJson = {
      'title': 'Bio',
      'summary': 'Plants make energy.',
      'points': ['Photosynthesis makes energy.', 'Chlorophyll absorbs light.'],
      'actions': [
        {'text': 'Submit the worksheet.', 'owner': 'Maya'},
        {'text': 'Read chapter one.'},
      ],
      'topics': [
        {'name': 'Plants', 'relatedPoints': [0, 1]},
      ],
      'links': [
        {'from': 0, 'to': 1, 'label': 'leads to'},
      ],
    };

    test('server shape maps onto Note', () {
      final n = noteFromProxyJson(serverJson, 'src', 'New note');
      expect(n.source, 'ai');
      expect(n.actions, ['Submit the worksheet. (Maya)', 'Read chapter one.']);
      expect(n.topics.single.points, [0, 1]);
      expect(n.links.single.label, 'leads to');
    });

    test('proxy success is labelled as the Voino server', () async {
      final client = MockClient((req) async {
        expect(req.url, url);
        expect(jsonDecode(req.body)['transcript'], 'hello world');
        expect(req.headers.containsKey('x-goog-api-key'), isFalse); // the app never sends a key to the server
        return http.Response(jsonEncode(serverJson), 200);
      });
      final r = await summarizeWithFallback('hello world', 'New note', useProxy: true, proxyUrl: url, client: client);
      expect(r.how, 'AI summary (Voino server)');
      expect(r.note.source, 'ai');
    });

    test('proxy failure falls back to rule-based notes with the reason', () async {
      final client = MockClient((_) async => http.Response('{}', 429));
      final r = await summarizeWithFallback('Plants use sunlight to grow.', 'New note', useProxy: true, proxyUrl: url, client: client);
      expect(r.how, startsWith('Rule-based extract (AI failed:'));
      expect(r.how, contains('rate limited'));
      expect(r.note.source, 'rule');
      expect(r.note.points, isNotEmpty);
    });

    test('network error and bad JSON both fall back', () async {
      final down = MockClient((_) async => throw Exception('offline'));
      expect((await summarizeWithFallback('Plants use sunlight to grow.', 'x', useProxy: true, proxyUrl: url, client: down)).note.source, 'rule');
      final junk = MockClient((_) async => http.Response('not json', 200));
      expect((await summarizeWithFallback('Plants use sunlight to grow.', 'x', useProxy: true, proxyUrl: url, client: junk)).note.source, 'rule');
    });

    test('own keys are tried first, then the server, then local', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.host);
        if (req.url.host == 'generativelanguage.googleapis.com') return http.Response('no', 500);
        return http.Response(jsonEncode(serverJson), 200);
      });
      final r = await summarizeWithFallback('hi there friend', 'x',
          keys: ['k1'], useKeys: true, useProxy: true, proxyUrl: url, client: client);
      expect(calls, ['generativelanguage.googleapis.com', 'example.test']);
      expect(r.how, 'AI summary (Voino server)');
    });

    test('nothing enabled gives plain rule-based notes and no requests', () async {
      final client = MockClient((_) async => fail('no request expected'));
      final r = await summarizeWithFallback('Plants use sunlight to grow.', 'x', keys: ['k'], client: client);
      expect(r.how, 'Rule-based extract');
    });
  });
}
