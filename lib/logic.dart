// Speech stitching and local (no-network) note extraction.

import 'dart:math' as math;

String cleanSpeech(String? v) => (v ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
List<String> _tokens(String t) => cleanSpeech(t).split(' ').where((x) => x.isNotEmpty).toList();
bool _eq(String a, String b) => a.toLowerCase() == b.toLowerCase();

String stitchSpeech(String previous, String incoming) {
  final a = _tokens(previous), b = _tokens(incoming);
  if (a.isEmpty) return b.join(' ');
  if (b.isEmpty) return a.join(' ');
  bool prefix(List<String> s, List<String> l) {
    for (var i = 0; i < s.length; i++) {
      if (!_eq(s[i], l[i])) return false;
    }
    return true;
  }

  if (b.length >= a.length && prefix(a, b)) return b.join(' ');
  if (a.length >= b.length && prefix(b, a)) return a.join(' ');
  for (var o = math.min(a.length, b.length); o > 0; o--) {
    var ok = true;
    for (var i = 0; i < o; i++) {
      if (!_eq(a[a.length - o + i], b[i])) {
        ok = false;
        break;
      }
    }
    if (ok) return [...a, ...b.sublist(o)].join(' ');
  }
  return [...a, ...b].join(' ');
}

/// A group of related points. [points] are indexes into [Note.points].
class Topic {
  Topic(this.name, this.points);
  final String name;
  final List<int> points;
}

/// A relationship between two points, by index into [Note.points].
class NoteLink {
  NoteLink(this.from, this.to, [this.label = '']);
  final int from, to;
  final String label;
}

class Note {
  Note(this.title, this.points, this.actions, this.transcript,
      {this.summary = '', List<Topic>? topics, List<NoteLink>? links, this.keyPoint, this.source = 'rule'})
      : topics = topics ?? [],
        links = links ?? [];
  final String title, transcript, summary;
  final List<String> points, actions;
  final List<Topic> topics;
  final List<NoteLink> links;
  final int? keyPoint;

  /// 'rule' for the local extractor, 'ai' for Gemini.
  final String source;
}

final _action = RegExp(
    r'\b(?:need to|have to|should|must|remember to|assignment|deadline|submit|send|finish|prepare|review|complete|due)\b',
    caseSensitive: false);
final _filler = RegExp(r'^(?:(?:um+|uh+|er+|okay|ok|so|well|like|right|anyway|you know|i mean)\b[,\s]*)+', caseSensitive: false);
final _word = RegExp(r"[a-z][a-z']{2,}");
const _stop = {
  'the', 'and', 'that', 'this', 'with', 'for', 'are', 'was', 'were', 'have', 'has', 'had', 'you', 'your', 'not', 'but',
  'can', 'will', 'would', 'could', 'should', 'from', 'they', 'them', 'their', 'there', 'then', 'than', 'which', 'what',
  'when', 'where', 'who', 'how', 'why', 'its', 'our', 'out', 'about', 'into', 'over', 'also', 'just', 'some', 'any',
  'all', 'one', 'more', 'most', 'very', 'been', 'being', 'does', 'did', 'because', 'these', 'those', 'such', 'each',
  'like', 'get', 'got', 'going', 'know', 'think', 'really', 'want', 'need', 'make', 'use', 'used', 'using', 'thing',
  'things', 'lot', 'much', 'many', 'now', 'here', 'yeah', 'okay', 'well', 'still', 'even', 'only', 'other', 'while',
};

List<String> _keywords(String s) =>
    _word.allMatches(s.toLowerCase()).map((m) => m.group(0)!).where((w) => !_stop.contains(w)).toList();

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Local extractive notes: filters filler, ranks sentences by keyword weight, groups
/// by dominant keyword and links neighbours. Source wording is kept; nothing is invented.
Note makeNotes(String transcript, [String title = 'New note']) {
  final src = cleanSpeech(transcript);
  final t = cleanSpeech(title).isEmpty ? 'New note' : cleanSpeech(title);
  if (src.isEmpty) return Note(t, [], [], '');

  var sentences = RegExp(r'[^.!?]+[.!?]?')
      .allMatches(src)
      .map((m) => _capitalize(m.group(0)!.trim().replaceFirst(_filler, '').trim()))
      .where((s) => s.isNotEmpty)
      .toList();
  final long = sentences.where((s) => s.split(' ').length >= 3).toList();
  if (long.isNotEmpty) sentences = long;

  final actions = {...sentences.where(_action.hasMatch)}.toList();
  final candidates = {...sentences.where((s) => !actions.contains(s))}.toList();

  final freq = <String, int>{};
  for (final s in candidates) {
    for (final w in _keywords(s).toSet()) {
      freq[w] = (freq[w] ?? 0) + 1;
    }
  }
  double score(String s) {
    final ws = _keywords(s).toSet();
    if (ws.isEmpty) return 0;
    return ws.fold<double>(0, (a, w) => a + (freq[w] ?? 0)) / math.pow(s.split(' ').length, 0.6);
  }

  // Short transcripts keep everything; longer ones keep the highest-scoring ~60%.
  final keep = candidates.length <= 4 ? candidates.length : math.min(8, (candidates.length * 0.6).ceil());
  final ranked = [...candidates]..sort((a, b) => score(b).compareTo(score(a)));
  final chosen = ranked.take(keep).toSet();
  final points = candidates.where(chosen.contains).toList();

  int? keyPoint;
  if (points.isNotEmpty) {
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if (score(points[i]) > score(points[best])) best = i;
    }
    keyPoint = best;
  }

  // Group by each point's most shared keyword; singletons collapse into "Other".
  String topicKey(String s) {
    final ws = _keywords(s);
    if (ws.isEmpty) return '';
    ws.sort((a, b) => (freq[b] ?? 0).compareTo(freq[a] ?? 0));
    return ws.first;
  }

  final groups = <String, List<int>>{};
  for (var i = 0; i < points.length; i++) {
    groups.putIfAbsent(topicKey(points[i]), () => []).add(i);
  }
  final named = groups.entries.where((e) => e.key.isNotEmpty && e.value.length > 1).toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  final topics = <Topic>[];
  final used = <int>{};
  for (final e in named.take(3)) {
    topics.add(Topic(_capitalize(e.key), e.value));
    used.addAll(e.value);
  }
  final rest = [for (var i = 0; i < points.length; i++) if (!used.contains(i)) i];
  if (rest.isNotEmpty) topics.add(Topic(topics.isEmpty ? 'Key points' : 'Other', rest));

  final links = <NoteLink>[
    for (final tp in topics)
      for (var i = 0; i + 1 < tp.points.length; i++) NoteLink(tp.points[i], tp.points[i + 1]),
  ];
  return Note(t, points, actions, src, topics: topics, links: links, keyPoint: keyPoint);
}

String exportText(Note n) {
  final b = StringBuffer(n.title)..write('\n\n');
  if (n.summary.isNotEmpty) b.write('Summary\n${n.summary}\n\n');
  b.write('Key points\n${n.points.isEmpty ? '(none yet)' : n.points.map((p) => '- $p').join('\n')}');
  b.write('\n\nThings to do\n${n.actions.isEmpty ? '(none yet)' : n.actions.map((a) => '[ ] $a').join('\n')}');
  b.write('\n\nOriginal transcript\n${n.transcript.isEmpty ? '(empty)' : n.transcript}\n');
  return b.toString();
}
