// Sentence classifier layer: tags each finalized transcript sentence as an
// action, decision, question or background. It never rewrites text; the original
// sentence is kept. Providers are swappable: the rule provider is local and
// always available, the hosted provider calls a free Gemma endpoint (opt-in,
// sends transcript text to a third party), an on-device model can be added later.

import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'classifier_data.dart';
import 'logic.dart';

enum SentenceKind { action, decision, question, background }

class Tagged {
  const Tagged(this.text, this.kind, [this.confidence]);
  final String text;
  final SentenceKind kind;

  /// 0..1 when the provider reports one, null for rule-based tags.
  final double? confidence;
}

abstract class SentenceClassifier {
  String get name;

  /// True when sentences leave the device.
  bool get sendsTextOffDevice;
  Future<List<Tagged>> classify(List<String> sentences);
}

final _question = RegExp(
    r'\?\s*$|^(?:kya|kyun|kyon|kaise|kab|kaun|kahan|kitna|kitne|क्या|क्यों|कैसे|कब|कौन|कहाँ|कितना|कितने)\b|^(?:क्या|क्यों|कैसे|कब|कौन|कहाँ|कितना|कितने)',
    caseSensitive: false);
final _decision = RegExp(
    r"\b(?:we decided|we will|we'll go with|let's go with|decided to|agreed|final decision|tay hua|tay kiya|fix hai|final hai|karenge)\b|(?:तय हुआ|तय किया|फैसला|तय है|करेंगे)",
    caseSensitive: false);

/// Local provider: reuses the Hindi/English action rules in logic.dart.
class RuleClassifier implements SentenceClassifier {
  @override
  String get name => 'rules';
  @override
  bool get sendsTextOffDevice => false;

  @override
  Future<List<Tagged>> classify(List<String> sentences) async => sentences.map(classifyOne).toList();

  static Tagged classifyOne(String s) {
    final t = cleanSpeech(s);
    if (_question.hasMatch(t)) return Tagged(t, SentenceKind.question);
    if (isActionSentence(t)) return Tagged(t, SentenceKind.action);
    if (_decision.hasMatch(t)) return Tagged(t, SentenceKind.decision);
    return Tagged(t, SentenceKind.background);
  }
}

/// Hosted provider for a Gemma model served by the Gemini API free tier.
/// Falls back to [fallback] on any error so notes always work.
class HostedGemmaClassifier implements SentenceClassifier {
  HostedGemmaClassifier(this.apiKey, {this.model = 'gemma-3-27b-it', http.Client? client, SentenceClassifier? fallback})
      : _client = client ?? http.Client(),
        fallback = fallback ?? RuleClassifier();
  final String apiKey, model;
  final http.Client _client;
  final SentenceClassifier fallback;

  @override
  String get name => 'hosted:$model';
  @override
  bool get sendsTextOffDevice => true;

  @override
  Future<List<Tagged>> classify(List<String> sentences) async {
    if (sentences.isEmpty) return [];
    try {
      final numbered = [for (var i = 0; i < sentences.length; i++) '$i: ${sentences[i]}'].join('\n');
      final prompt = 'Label each numbered sentence (English, Hindi or Hinglish) as exactly one of: '
          'action, decision, question, background. Reply with ONLY a JSON array of strings, one label per sentence, in order.\n$numbered';
      final res = await _client
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
            body: jsonEncode({
              'contents': [
                {'parts': [{'text': prompt}]}
              ],
              'generationConfig': {'temperature': 0},
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return fallback.classify(sentences);
      final text = ((jsonDecode(res.body)['candidates'] as List).first['content']['parts'] as List).first['text'] as String;
      return parseLabels(text, sentences) ?? fallback.classify(sentences);
    } catch (_) {
      return fallback.classify(sentences);
    }
  }

  /// Parses the model reply; null when it is not a valid label array of the right length.
  static List<Tagged>? parseLabels(String reply, List<String> sentences) {
    final m = RegExp(r'\[[\s\S]*\]').firstMatch(reply);
    if (m == null) return null;
    try {
      final labels = jsonDecode(m.group(0)!);
      if (labels is! List || labels.length != sentences.length) return null;
      final out = <Tagged>[];
      for (var i = 0; i < labels.length; i++) {
        final k = SentenceKind.values.where((e) => e.name == '${labels[i]}'.toLowerCase().trim());
        if (k.isEmpty) return null;
        out.add(Tagged(cleanSpeech(sentences[i]), k.first));
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}

/// Tiny on-device provider: multinomial Naive Bayes over word and character n-gram
/// features, trained at startup from [kTrainingSentences] (about a hundred sentences, <10 ms).
/// Classifying a sentence takes microseconds, so it can run on every finalized chunk.
class NaiveBayesClassifier implements SentenceClassifier {
  NaiveBayesClassifier([List<List<String>>? data]) {
    for (final row in data ?? kTrainingSentences) {
      final k = SentenceKind.values.firstWhere((e) => e.name == row[0]);
      _docs[k] = (_docs[k] ?? 0) + 1;
      _total++;
      for (final f in _features(row[1])) {
        final m = _counts.putIfAbsent(k, () => {});
        m[f] = (m[f] ?? 0) + 1;
        _sums[k] = (_sums[k] ?? 0) + 1;
        _vocab.add(f);
      }
    }
  }
  final _docs = <SentenceKind, int>{};
  final _counts = <SentenceKind, Map<String, int>>{};
  final _sums = <SentenceKind, int>{};
  final _vocab = <String>{};
  int _total = 0;

  @override
  String get name => 'naive-bayes';
  @override
  bool get sendsTextOffDevice => false;

  static List<String> _features(String s) {
    final t = cleanSpeech(s).toLowerCase();
    final words = RegExp(r"[a-z0-9\u0900-\u097F']+").allMatches(t).map((m) => m.group(0)!).toList();
    final f = <String>[];
    for (var i = 0; i < words.length; i++) {
      f.add('w:${words[i]}');
      if (i + 1 < words.length) f.add('b:${words[i]}_${words[i + 1]}');
      final w = '<${words[i]}>';
      for (var n = 3; n <= 4; n++) {
        for (var j = 0; j + n <= w.length; j++) {
          f.add('c:${w.substring(j, j + n)}');
        }
      }
    }
    if (t.endsWith('?')) f.add('q:mark');
    if (words.isNotEmpty) f.add('first:${words.first}');
    if (words.length >= 2) f.add('last:${words.last}');
    return f;
  }

  Tagged classifyOne(String s) {
    final f = _features(s);
    SentenceKind? best;
    var bestScore = double.negativeInfinity;
    final scores = <SentenceKind, double>{};
    for (final k in SentenceKind.values) {
      var sc = math.log((_docs[k] ?? 0) + 1) - math.log(_total + SentenceKind.values.length);
      final c = _counts[k] ?? const {};
      final denom = (_sums[k] ?? 0) + _vocab.length + 1;
      for (final x in f) {
        sc += math.log((c[x] ?? 0) + 1) - math.log(denom);
      }
      scores[k] = sc;
      if (sc > bestScore) {
        bestScore = sc;
        best = k;
      }
    }
    // Softmax over the log-scores gives a rough confidence.
    var z = 0.0;
    for (final v in scores.values) {
      z += math.exp(v - bestScore);
    }
    return Tagged(cleanSpeech(s), best!, 1 / z);
  }

  @override
  Future<List<Tagged>> classify(List<String> sentences) async => sentences.map(classifyOne).toList();
}

/// Rules first for strong cues (question mark, explicit action phrase), Naive Bayes otherwise.
class HybridClassifier implements SentenceClassifier {
  HybridClassifier([NaiveBayesClassifier? nb]) : _nb = nb ?? NaiveBayesClassifier();
  final NaiveBayesClassifier _nb;
  @override
  String get name => 'hybrid';
  @override
  bool get sendsTextOffDevice => false;

  @override
  Future<List<Tagged>> classify(List<String> sentences) async => sentences.map((s) {
        final r = RuleClassifier.classifyOne(s);
        return r.kind == SentenceKind.background ? _nb.classifyOne(s) : r;
      }).toList();
}
