import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voino/gemini.dart';
import 'package:voino/logic.dart';

void main() {
  String longText(int sentences, {int wordsPer = 12}) {
    final b = StringBuffer();
    for (var i = 0; i < sentences; i++) {
      b.write('Sentence number $i about topic${i % 7} with several descriptive words here. ');
    }
    return b.toString();
  }

  group('chunkTranscript', () {
    test('short text stays one chunk', () {
      expect(chunkTranscript('Hello world.'), ['Hello world.']);
      expect(chunkTranscript('   '), isEmpty);
    });
    test('long text splits at sentence boundaries and never exceeds max', () {
      final src = longText(2000); // ~130k chars
      final chunks = chunkTranscript(src, maxChars: 10000);
      expect(chunks.length, greaterThan(3));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(10000 + 100));
      }
      // nothing dropped: joined chunks contain every sentence
      final joined = chunks.join(' ');
      for (final i in [0, 500, 1234, 1999]) {
        expect(joined, contains('Sentence number $i '));
      }
    });
    test('one over-long sentence is hard-split, not dropped', () {
      final src = 'x' * 25000;
      final chunks = chunkTranscript(src, maxChars: 10000);
      expect(chunks.length, 3);
      expect(chunks.join().replaceAll(' ', '').length, 25000);
    });
  });

  group('mergePartNotes', () {
    Note part(String marker, int offset) => Note(
          'Part',
          ['point $marker one', 'point $marker two'],
          ['do $marker'],
          'transcript $marker',
          summary: 'Summary of $marker.',
          topics: [Topic('t$marker', [0, 1])],
          links: [NoteLink(0, 1, 'leads')],
          keyPoint: offset,
          source: 'ai',
        );
    test('keeps every part content with re-indexed topics and links', () {
      final m = mergePartNotes([part('A', 0), part('B', 1)], 'My meeting', 'full transcript');
      expect(m.points, hasLength(4));
      expect(m.actions, ['do A', 'do B']);
      expect(m.topics, hasLength(2));
      expect(m.topics[1].points, [2, 3]);
      expect(m.links, hasLength(2));
      expect(m.links[1].from, 2);
      expect(m.links[1].to, 3);
      expect(m.keyPoint, 0);
      expect(m.summary, contains('Summary of A.'));
      expect(m.summary, contains('Summary of B.'));
      expect(m.transcript, 'full transcript');
      expect(m.source, 'ai');
    });
    test('dedupes repeated points and actions', () {
      final a = part('A', 0);
      final m = mergePartNotes([a, a], 't', 'x');
      expect(m.points, hasLength(2));
      expect(m.actions, hasLength(1));
    });
    test('single part passes through unchanged', () {
      final a = part('A', 0);
      expect(identical(mergePartNotes([a], 't', 'x'), a), isTrue);
    });
  });

  group('long-transcript clients', () {
    final geminiResponse = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text': '{"title":"T","summary":"A fact about this part.","points":["point alpha"],"actions":["do alpha"],"topics":[{"name":"g","points":[0]}],"links":[],"keyPoint":0}'
              }
            ]
          }
        }
      ]
    });

    test('GeminiClient chunks long transcripts instead of truncating', () async {
      final bodies = <String>[];
      final mock = MockClient((req) async {
        bodies.add(req.body);
        return http.Response(geminiResponse, 200, headers: {'content-type': 'application/json'});
      });
      final src = longText(1200); // ~78k chars, over the old 30k silent cut
      final c = GeminiClient(['k1'], client: mock);
      final n = await c.summarize(src, title: 'Long discussion');
      expect(c.lastParts, greaterThanOrEqualTo(2));
      expect(bodies.length, c.lastParts);
      // no single request carries the whole transcript, and nothing was silently cut:
      // chunk texts sent must cover the tail of the transcript
      final tail = src.substring(src.length - 200);
      expect(bodies.join(), contains(tail.trim().split(' ').take(5).join(' ')));
      expect(n.points, isNotEmpty);
      expect(n.summary, isNotEmpty);
    });

    test('ProxyClient chunks under the server cap', () async {
      final sizes = <int>[];
      final proxyResponse = jsonEncode({
        'title': 'T',
        'summary': 'A fact about this part.',
        'points': ['point alpha'],
        'actions': ['do alpha'],
        'topics': [{'name': 'g', 'relatedPoints': [0]}],
        'links': [],
        'keyPoint': 0,
      });
      final mock = MockClient((req) async {
        final t = (jsonDecode(req.body) as Map)['transcript'] as String;
        sizes.add(t.length);
        return http.Response(proxyResponse, 200, headers: {'content-type': 'application/json'});
      });
      final src = longText(600); // ~39k chars
      final p = ProxyClient(Uri.parse('https://x.test/api/summarize'), client: mock);
      final n = await p.summarize(src, title: 'Long discussion');
      expect(p.lastParts, greaterThanOrEqualTo(2));
      expect(sizes.length, p.lastParts);
      for (final s in sizes) {
        expect(s, lessThanOrEqualTo(ProxyClient.proxyMaxChars + 200));
      }
      expect(n.points, isNotEmpty);
    });

    test('summarizeWithFallback still falls back to local on total failure', () async {
      final mock = MockClient((req) async => http.Response('nope', 500));
      final r = await summarizeWithFallback(
        'We need to submit the report by Friday. The design review went well.',
        't',
        keys: const ['k'],
        useKeys: true,
        useProxy: false,
        client: mock,
      );
      expect(r.note.source, 'rule');
      expect(r.how, contains('Rule-based extract'));
      expect(r.how, contains('AI failed'));
    });
  });
  semanticMergeTests();
  orphanActionTests();
}

// --- semantic merge coverage (parent review): end items, dedup, boundaries ---
void semanticMergeTests() {
  group('mergePartNotes semantic coverage', () {
    test('decisions and actions from the LAST chunk survive unchanged', () {
      final early = Note('P', ['opening context point'], ['early setup task'], 'start',
          summary: 'We opened with context.', source: 'ai');
      final late = Note(
        'P',
        ['final decision: ship on Friday'],
        ['Sanskar sends the recap tonight', 'book the review slot'],
        'end',
        summary: 'We decided to ship Friday.',
        source: 'ai',
      );
      final m = mergePartNotes([early, late], 'Meeting', 'start end');
      expect(m.points, contains('final decision: ship on Friday'));
      expect(m.actions, contains('Sanskar sends the recap tonight'));
      expect(m.actions, contains('book the review slot'));
      // summary order is chronological: opening before decision
      expect(m.summary.indexOf('opened with context'),
          lessThan(m.summary.indexOf('decided to ship Friday')));
    });

    test('duplicate action across chunks appears once, variants both kept', () {
      final a = Note('P', ['p1'], ['send the recap'], 'a', summary: 's1', source: 'ai');
      final b = Note('P', ['p2'], ['Send the recap', 'send the recap to investors'], 'b',
          summary: 's2', source: 'ai');
      final m = mergePartNotes([a, b], 't', 'a b');
      expect(m.actions.where((x) => x.toLowerCase() == 'send the recap'), hasLength(1));
      expect(m.actions, contains('send the recap to investors'));
    });

    test('topics from different chunks stay separate groups (no cross-chunk index bleed)', () {
      final a = Note('P', ['alpha one', 'alpha two'], [], 'a',
          topics: [Topic('Alpha', [0, 1])], source: 'ai');
      final b = Note('P', ['beta one'], [], 'b',
          topics: [Topic('Beta', [0])], source: 'ai');
      final m = mergePartNotes([a, b], 't', 'a b');
      expect(m.topics.map((t) => t.name), ['Alpha', 'Beta']);
      expect(m.topics[0].points, [0, 1]);
      expect(m.topics[1].points, [2]);
      expect(m.points[2], 'beta one');
    });

    test('mixed-source parts are labeled rule, not AI', () {
      final ai = Note('P', ['p'], [], 'a', summary: 's', source: 'ai');
      final rule = Note('P', ['q'], [], 'b', summary: 's', source: 'rule');
      expect(mergePartNotes([ai, rule], 't', 'a b').source, 'rule');
    });

    test('empty summaries and empty point lists merge safely', () {
      final a = Note('P', <String>[], <String>[], 'a', source: 'ai');
      final b = Note('P', ['real point'], ['real action'], 'b', summary: 'only summary', source: 'ai');
      final m = mergePartNotes([a, b], 't', 'a b');
      expect(m.points, ['real point']);
      expect(m.actions, ['real action']);
      expect(m.summary, 'only summary');
    });
  });
}

// --- orphan action guard + notes action label ---
void orphanActionTests() {
  group('orphan deadline actions', () {
    test('bare "deadline for that" merges into the sentence it refers to', () {
      final n = makeNotes(
        'Someone has to reply to the design agency about the logo revision. The deadline for that is Wednesday. '
        'We need to finish the pitch deck by Thursday.');
      expect(n.actions.any((a) => a.contains('logo revision') && a.contains('Wednesday')), isTrue);
      expect(n.actions.any((a) => a.trim() == 'The deadline for that is Wednesday.'), isFalse);
      // the referred-to sentence is absorbed into the action, not duplicated as a point
      expect(n.points.any((p) => p.contains('logo revision')), isFalse);
    });
    test('concrete standalone action mentioning "that" is NOT merged', () {
      final n = makeNotes(
        'The pricing page needs a simpler layout. I should send that report. We must submit the form by Friday.');
      expect(n.actions.any((a) => a.trim() == 'I should send that report.'), isTrue);
    });
    test('deadline with its own subject stays separate', () {
      final n = makeNotes(
        'Priya will draft the market slide tonight. The pitch deck deadline is Thursday.');
      expect(n.actions.any((a) => a.contains('pitch deck deadline')), isTrue);
    });
  });
}
