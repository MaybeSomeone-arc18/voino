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
}
