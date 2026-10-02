// Sentence classifier layer: tags each finalized transcript sentence as an
// action, decision, question or background. It never rewrites text; the original
// sentence is kept. Providers are swappable: the rule provider is local and
// always available, the hosted provider calls a free Gemma endpoint (opt-in,
// sends transcript text to a third party), an on-device model can be added later.

import 'dart:convert';
import 'package:http/http.dart' as http;
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
