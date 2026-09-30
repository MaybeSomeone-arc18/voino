import 'dart:convert';
import 'package:flutter/painting.dart' show Rect;
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

  group('board layout', () {
    test('no two cards overlap, even with many topics and actions', () {
      final n = Note('T', List.generate(9, (i) => 'Point $i.'), ['Do A now.', 'Do B now.', 'Do C now.'], 't',
          topics: [Topic('One', [0, 1, 2]), Topic('Two', [3, 4]), Topic('Three', [5, 6, 7]), Topic('Other', [8])]);
      final b = buildBoard(n);
      final rects = [for (final c in b.cards) Rect.fromLTWH(c.x, c.y, cardSize.width, cardSize.height)];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse, reason: '${b.cards[i].id} overlaps ${b.cards[j].id}');
        }
      }
      expect(b.cards.where((c) => c.type == 'point').every((c) => c.color == 'mint'), isTrue);
      expect(b.cards.where((c) => c.type == 'action').every((c) => c.color == 'rose'), isTrue);
    });

    test('decisions get circles in addition to the key point, capped at three', () {
      final n = Note('T', ['We decided to ship Friday.', 'Sky is blue.', 'Everyone agreed to the budget.', 'The team chose Flutter.'], [], 't',
          topics: [Topic('All', [0, 1, 2, 3])], keyPoint: 1);
      final circles = buildBoard(n).shapes.where((s) => s.type == 'circle').toList();
      expect(circles.length, 3);
      expect(circles.map((c) => c.label), containsAll(['key', 'decision']));
    });

    test('every topic gets a labelled box and arrows are labelled', () {
      final b = buildBoard(makeNotes(lecture, 'Bio'));
      expect(b.shapes.where((s) => s.type == 'box').every((s) => s.label.isNotEmpty), isTrue);
      final ai = noteFromGeminiJson({
        'title': 'x', 'summary': '', 'points': ['A.', 'B.'], 'actions': [], 'topics': [{'name': 'T', 'points': [0, 1]}],
        'links': [{'from': 0, 'to': 1, 'label': 'causes'}],
      }, 't', 'New note');
      expect(buildBoard(ai).links.any((l) => l.label == 'causes'), isTrue);
    });
  });

  group('board layout (mind-map)', () {
    Note big() => Note('Launch', List.generate(11, (i) => 'Point number $i here.'), ['Do A now.', 'Do B now.'], 't',
        summary: 'A summary.',
        topics: [Topic('One', [0, 1, 2, 3, 4, 5]), Topic('Two', [6, 7]), Topic('Three', [8, 9, 10])],
        links: [NoteLink(0, 7, 'causes'), NoteLink(3, 9, 'leads to')],
        keyPoint: 0);

    test('title is central, groups sit on both sides, boxes contain their cards', () {
      final b = buildBoard(big());
      final title = b.cards.firstWhere((c) => c.type == 'title');
      final xs = b.cards.where((c) => c.type != 'title').map((c) => c.x);
      expect(xs.any((x) => x < title.x), isTrue);
      expect(xs.any((x) => x > title.x), isTrue);
      final boxes = b.shapes.where((s) => s.type == 'box').toList();
      expect(boxes.length, 4); // 3 topics + To do
      for (final c in b.cards.where((c) => c.type != 'title')) {
        final r = Rect.fromLTWH(c.x, c.y, cardSize.width, cardSize.height);
        expect(boxes.where((bx) => bx.rect.contains(r.topLeft) && bx.rect.contains(r.bottomRight)).length, 1, reason: c.id);
      }
    });

    test('group boxes never overlap each other or the title, and stay on the canvas', () {
      final b = buildBoard(big());
      final boxes = b.shapes.where((s) => s.type == 'box').map((s) => s.rect).toList();
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          expect(boxes[i].overlaps(boxes[j]), isFalse);
        }
      }
      final t = b.cards.first;
      final tr = Rect.fromLTWH(t.x, t.y, cardSize.width, cardSize.height);
      expect(boxes.any((r) => r.overlaps(tr)), isFalse);
      expect(b.cards.every((c) => c.x >= 0 && c.y >= 0 && c.x <= 4000 && c.y <= 4000), isTrue);
    });

    test('point links keep their labels and every arrow ends on a real card', () {
      final b = buildBoard(big());
      final ids = b.cards.map((c) => c.id).toSet();
      expect(b.links.every((l) => ids.contains(l.from) && ids.contains(l.to)), isTrue);
      expect(b.links.where((l) => l.label == 'causes' && l.from == 'p0' && l.to == 'p7').length, 1);
      expect(b.links.where((l) => l.from == 'title').length, 4);
    });

    test('empty and single-topic notes still lay out', () {
      expect(buildBoard(Note('Only title', [], [], '')).cards.single.type, 'title');
      final one = buildBoard(Note('T', ['A point here.'], [], 't', topics: [Topic('All', [0])]));
      expect(one.cards.length, 2);
    });

    test('/api/summarize JSON becomes a board that survives a download and re-open', () {
      final note = noteFromProxyJson({
        'title': 'Sprint',
        'summary': 'We planned.',
        'points': ['We decided to ship Friday.', 'Testing is slow.', 'Docs are late.'],
        'actions': [{'text': 'Fix tests', 'owner': 'Maya'}],
        'topics': [{'name': 'Release', 'relatedPoints': [0, 1]}, {'name': 'Docs', 'relatedPoints': [2]}],
        'links': [{'from': 1, 'to': 0, 'label': 'blocks'}],
        'keyPoint': 0,
      }, 't', 'New note');
      final b = buildBoard(note);
      expect(b.cards.where((c) => c.type == 'point').every((c) => c.color == 'mint'), isTrue);
      expect(b.cards.singleWhere((c) => c.type == 'action').text, 'Fix tests (Maya)');
      expect(b.shapes.where((s) => s.type == 'circle').map((s) => s.label), ['key']);
      final json = jsonEncode({
        'title': 'Sprint',
        'transcript': 't',
        'cards': b.cards.map((c) => c.toJson()).toList(),
        'connections': b.links.map((l) => l.toJson()).toList(),
        'shapes': b.shapes.map((s) => s.toJson()).toList(),
      });
      final r = parseBoardJson(json)!;
      expect(r.board.cards.length, b.cards.length);
      expect(r.board.links.length, b.links.length);
      expect(r.board.shapes.length, b.shapes.length);
      expect(r.board.links.any((l) => l.label == 'blocks'), isTrue);
    });
  });

  group('board JSON validation (safeCards / safeConnections / safeShapes)', () {
    test('safeCards drops bad types, non-text, duplicate ids and clamps coordinates and length', () {
      final cards = safeCards([
        {'id': 'a', 'type': 'point', 'text': 'ok', 'x': 99999, 'y': -5, 'color': 'nope'},
        {'id': 'a', 'type': 'point', 'text': 'dup'},
        {'id': 'b', 'type': 'script', 'text': 'bad type'},
        {'id': 'c', 'type': 'idea', 'text': 42},
        {'id': 'd', 'type': 'action', 'text': 'x' * 5000, 'x': double.nan, 'color': 'rose'},
        'junk',
        null,
      ]);
      expect(cards.map((c) => c.id), ['a', 'd']);
      expect(cards[0].x, 4000);
      expect(cards[0].y, 0);
      expect(cards[0].color, 'mint');
      expect(cards[1].text.length, 1400);
      expect(cards[1].x, 24);
      expect(cards[1].color, 'rose');
    });

    test('safeCards caps at 60 and tolerates non-lists', () {
      expect(safeCards([for (var i = 0; i < 100; i++) {'id': '$i', 'type': 'idea', 'text': 't'}]).length, 60);
      expect(safeCards('nope'), isEmpty);
      expect(safeCards(null), isEmpty);
    });

    test('safeConnections keeps only arrows between known, different cards', () {
      final links = safeConnections([
        {'from': 'a', 'to': 'b', 'label': 'causes'},
        {'from': 'a', 'to': 'ghost'},
        {'from': 'a', 'to': 'a'},
        {'from': 'b', 'to': 'a', 'label': 'y' * 200},
        7,
      ], {'a', 'b'});
      expect(links.length, 2);
      expect(links[0].label, 'causes');
      expect(links[1].label.length, 60);
      expect(safeConnections({'not': 'a list'}, {'a'}), isEmpty);
    });

    test('safeShapes keeps circles and boxes, clamps size and drops unknown shapes', () {
      final shapes = safeShapes([
        {'type': 'circle', 'x': 10, 'y': 20, 'w': 5, 'h': 99999, 'label': 'key'},
        {'type': 'box', 'x': 0, 'y': 0},
        {'type': 'star', 'x': 1, 'y': 1},
        {'type': 'box', 'x': 'left', 'y': 1},
        'junk',
      ]);
      expect(shapes.length, 2);
      expect(shapes[0].rect.width, 8);
      expect(shapes[0].rect.height, 800);
      expect(shapes[1].rect.width, 80);
    });

    test('parseBoardJson rejects non-boards and accepts the legacy "links" key', () {
      expect(parseBoardJson('[]'), isNull);
      expect(parseBoardJson('{"cards": 3}'), isNull);
      final r = parseBoardJson(jsonEncode({
        'cards': [{'id': 'a', 'type': 'idea', 'text': 'A'}, {'id': 'b', 'type': 'idea', 'text': 'B'}],
        'links': [{'from': 'a', 'to': 'b', 'label': 'x'}],
      }))!;
      expect(r.board.links.single.label, 'x');
      expect(r.board.shapes, isEmpty);
    });
  });
}
