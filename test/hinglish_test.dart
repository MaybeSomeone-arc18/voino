import 'package:flutter_test/flutter_test.dart';
import 'package:voino/classifier.dart';
import 'package:voino/logic.dart';

void main() {
  group('Hindi / Hinglish notes', () {
    test('Devanagari action items are detected and sentences split on danda', () {
      final n = makeNotes('कल तक असाइनमेंट जमा करना है। प्रोजेक्ट का डेटाबेस बहुत बड़ा है। डेटाबेस में तीन टेबल हैं।');
      expect(n.actions, ['कल तक असाइनमेंट जमा करना है।']);
      expect(n.points.length, 2);
    });
    test('romanized Hinglish action items are detected', () {
      final n = makeNotes('Kal tak assignment submit karna hai. Hume client ko report bhejni hai. Database ka design important hai.');
      expect(n.actions.length, 2);
      expect(n.points, ['Database ka design important hai.']);
    });
    test('English behaviour unchanged', () {
      final n = makeNotes('We need to send the report. The database has three tables.');
      expect(n.actions, ['We need to send the report.']);
    });
  });

  group('classifier', () {
    test('rule provider tags kinds', () async {
      final r = await RuleClassifier().classify(['Kya deadline kal hai?', 'Report bhejni hai.', 'Hum pricing par tay hua.', 'Weather achha tha.']);
      expect(r.map((e) => e.kind), [SentenceKind.question, SentenceKind.action, SentenceKind.decision, SentenceKind.background]);
    });
    test('hosted parser rejects wrong length and unknown labels', () {
      expect(HostedGemmaClassifier.parseLabels('["action"]', ['a', 'b']), isNull);
      expect(HostedGemmaClassifier.parseLabels('["foo","action"]', ['a', 'b']), isNull);
      final ok = HostedGemmaClassifier.parseLabels('```json\n["Action","background"]\n```', ['a', 'b'])!;
      expect(ok.map((e) => e.kind), [SentenceKind.action, SentenceKind.background]);
    });
  });

  group('fast on-device classifier', () {
    final held = <List<String>>[
    ["action", "Isko Wednesday tak finish karna hoga."],
    ["action", "Please share the notes with the team."],
    ["action", "Mujhe lab report jama karni hai kal."],
    ["action", "I should call the landlord tomorrow."],
    ["action", "Client ko revised quote bhej dena."],
    ["action", "Hume tests likhne padenge before release."],
    ["action", "Aap sab apna feedback form bhar dena."],
    ["action", "We have to renew the domain this week."],
    ["decision", "Toh decide hua ki hum Gemini nahi lenge."],
    ["decision", "We have agreed to cut the scope for v1."],
    ["decision", "Final hai, standup roz subah 10 baje hoga."],
    ["decision", "We chose React over Vue for the dashboard."],
    ["decision", "Hum monthly plan hi rakhenge, yeh tay hai."],
    ["decision", "Okay, we're going with option B."],
    ["question", "Kya tum kal free ho?"],
    ["question", "What time does the demo start?"],
    ["question", "Ye bug kab fix hoga?"],
    ["question", "Which model should we use for this?"],
    ["question", "Kaun si library better hai yahan?"],
    ["question", "Do we have enough budget for this?"],
    ["question", "Kitne baje call hai?"],
    ["question", "Is this deadline fixed?"],
    ["background", "Humari team Bangalore mein baithti hai."],
    ["background", "The algorithm runs in linear time."],
    ["background", "Kal rain ki wajah se traffic tha."],
    ["background", "Whisper is a speech recognition model from OpenAI."],
    ["background", "Yeh feature pichle sprint mein banaya tha."],
    ["background", "The lecture covered cell division in detail."],
    ["background", "Usne bataya ki uska flight late tha."],
    ["background", "Our average response time was two seconds."],
    ];
    test('naive bayes and hybrid are accurate on held-out Hinglish sentences', () async {
      for (final c in <SentenceClassifier>[NaiveBayesClassifier(), HybridClassifier()]) {
        final r = await c.classify([for (final h in held) h[1]]);
        var ok = 0;
        for (var i = 0; i < held.length; i++) {
          if (r[i].kind.name == held[i][0]) ok++;
        }
        expect(ok / held.length, greaterThanOrEqualTo(0.85), reason: c.name);
      }
    });
    test('classifying is fast', () async {
      final nb = NaiveBayesClassifier();
      final sw = Stopwatch()..start();
      await nb.classify([for (var i = 0; i < 200; i++) held[i % held.length][1]]);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });
}
