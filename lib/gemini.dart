import 'dart:convert';
import 'package:http/http.dart' as http;
import 'logic.dart';

class GeminiException implements Exception {
  GeminiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

const _maxTranscript = 30000;

const _prompt = 'You turn a raw speech transcript into faithful notes. Use ONLY what the transcript says. '
    'Do not invent owners, dates, numbers, decisions or facts. Fix obvious speech-recognition slips only when the meaning is clear. '
    'Write a 2-4 sentence summary, concise key points (each a complete sentence), and action items only if someone actually said to do something '
    '(include the owner only if named). Group points into 1-4 topics using point indexes (0-based). '
    'Add links between related points with a short verb-phrase label (e.g. "causes", "leads to", "example of"), using point indexes. '
    'keyPoint is the index of the single most important point.';

Map<String, dynamic> get _schema => {
      'type': 'OBJECT',
      'properties': {
        'title': {'type': 'STRING'},
        'summary': {'type': 'STRING'},
        'points': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
        'actions': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
        'topics': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'name': {'type': 'STRING'},
              'points': {'type': 'ARRAY', 'items': {'type': 'INTEGER'}},
            },
            'required': ['name', 'points'],
          },
        },
        'links': {
          'type': 'ARRAY',
          'items': {
            'type': 'OBJECT',
            'properties': {
              'from': {'type': 'INTEGER'},
              'to': {'type': 'INTEGER'},
              'label': {'type': 'STRING'},
            },
            'required': ['from', 'to', 'label'],
          },
        },
        'keyPoint': {'type': 'INTEGER'},
      },
      'required': ['title', 'summary', 'points', 'actions', 'topics', 'links'],
    };

/// Validates model output: drops bad indexes, dedupes, and caps sizes.
Note noteFromGeminiJson(Map<String, dynamic> j, String transcript, String fallbackTitle) {
  List<String> strings(dynamic v, int max) => v is List
      ? v.whereType<String>().map(cleanSpeech).where((s) => s.isNotEmpty).toSet().take(max).toList()
      : <String>[];
  final points = strings(j['points'], 20);
  final actions = strings(j['actions'], 20);
  bool ok(dynamic i) => i is int && i >= 0 && i < points.length;

  final topics = <Topic>[];
  final assigned = <int>{};
  if (j['topics'] is List) {
    for (final t in (j['topics'] as List).take(4)) {
      if (t is! Map) continue;
      final idx = ((t['points'] as List?) ?? []).where(ok).cast<int>().where((i) => assigned.add(i)).toList();
      final name = cleanSpeech(t['name'] as String?);
      if (idx.isNotEmpty) topics.add(Topic(name.isEmpty ? 'Topic' : name, idx));
    }
  }
  final rest = [for (var i = 0; i < points.length; i++) if (!assigned.contains(i)) i];
  if (rest.isNotEmpty) topics.add(Topic(topics.isEmpty ? 'Key points' : 'Other', rest));

  final links = <NoteLink>[];
  if (j['links'] is List) {
    for (final l in (j['links'] as List).take(30)) {
      if (l is Map && ok(l['from']) && ok(l['to']) && l['from'] != l['to']) {
        links.add(NoteLink(l['from'] as int, l['to'] as int, cleanSpeech(l['label'] as String?)));
      }
    }
  }
  final title = cleanSpeech(j['title'] as String?);
  return Note(
    cleanSpeech(fallbackTitle).isNotEmpty && fallbackTitle != 'New note' ? cleanSpeech(fallbackTitle) : (title.isEmpty ? 'New note' : title),
    points,
    actions,
    cleanSpeech(transcript),
    summary: cleanSpeech(j['summary'] as String?),
    topics: topics,
    links: links,
    keyPoint: ok(j['keyPoint']) ? j['keyPoint'] as int : null,
    source: 'ai',
  );
}

/// Calls Gemini directly with user-supplied keys, rotating to the next key on any failure.
class GeminiClient {
  GeminiClient(List<String> keys, {http.Client? client, this.model = 'gemini-2.5-flash'})
      : keys = keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList(),
        _client = client ?? http.Client();
  final List<String> keys;
  final String model;
  final http.Client _client;
  static int _next = 0;

  Future<Note> summarize(String transcript, {String title = 'New note'}) async {
    if (keys.isEmpty) throw GeminiException('No Gemini API key set.');
    final text = transcript.length > _maxTranscript ? transcript.substring(0, _maxTranscript) : transcript;
    final body = jsonEncode({
      'systemInstruction': {'parts': [{'text': _prompt}]},
      'contents': [{'role': 'user', 'parts': [{'text': text}]}],
      'generationConfig': {'responseMimeType': 'application/json', 'responseSchema': _schema, 'temperature': 0.2},
    });
    GeminiException? last;
    for (var n = 0; n < keys.length; n++) {
      final key = keys[(_next + n) % keys.length];
      try {
        final res = await _client
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
              headers: {'content-type': 'application/json', 'x-goog-api-key': key},
              body: body,
            )
            .timeout(const Duration(seconds: 45));
        if (res.statusCode == 200) {
          _next = (_next + n + 1) % keys.length; // rotate for the next request
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final raw = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
          if (raw is! String) throw GeminiException('Gemini returned no text.');
          return noteFromGeminiJson(jsonDecode(raw) as Map<String, dynamic>, transcript, title);
        }
        last = GeminiException('Gemini error ${res.statusCode}', res.statusCode);
      } on GeminiException catch (e) {
        last = e;
      } catch (e) {
        last = GeminiException('Could not reach Gemini.');
      }
    }
    throw last ?? GeminiException('Gemini failed.');
  }
}
