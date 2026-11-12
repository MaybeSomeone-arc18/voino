import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A small device-local history of notes the user explicitly cleared.
/// Archiving happens only on an explicit Clear/New action - never
/// automatically, so nothing the user is still editing is silently moved.
/// Keeps at most [maxEntries]; archiving past the cap drops the OLDEST
/// entry. This is not cloud backup.
class DraftHistory extends ChangeNotifier {
  DraftHistory({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
    this.maxEntries = 5,
  })  : _read = read ??
            (() => const FlutterSecureStorage().read(key: 'voino_history_v1')),
        _write = write ??
            ((s) => const FlutterSecureStorage()
                .write(key: 'voino_history_v1', value: s));

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final int maxEntries;

  final List<DraftHistoryEntry> entries = [];
  bool ready = false;
  String error = '';

  void _notify() {
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final raw = await _read();
      entries.clear();
      if (raw != null && raw.isNotEmpty) {
        final value = jsonDecode(raw);
        if (value is! List) throw const FormatException('bad history');
        for (final e in value) {
          if (e is Map &&
              e['id'] is String &&
              e['title'] is String &&
              e['savedAt'] is String &&
              e['draft'] is Map<String, dynamic>) {
            entries.add(DraftHistoryEntry(
              id: e['id'] as String,
              title: e['title'] as String,
              savedAt: e['savedAt'] as String,
              draft: e['draft'] as Map<String, dynamic>,
            ));
          }
        }
      }
      ready = true;
      error = '';
    } catch (_) {
      // A corrupt history must never block the app or the live draft.
      entries.clear();
      ready = true;
      error = 'Recent notes could not be read.';
    }
    _notify();
  }

  /// Archives a draft snapshot. Returns false when there is nothing worth
  /// keeping (empty title and transcript and no board content).
  Future<bool> archive(Map<String, dynamic> draft) async {
    final title = (draft['title'] as String? ?? '').trim();
    final transcript = (draft['transcript'] as String? ?? '').trim();
    final summary = (draft['summary'] as String? ?? '').trim();
    if (title.isEmpty && transcript.isEmpty && summary.isEmpty) return false;
    // Opening a recent note auto-archives the one it replaces; skip when the
    // newest entry already holds exactly this content, so reopening notes
    // does not pile up duplicates.
    if (entries.isNotEmpty) {
      final d = entries.first.draft;
      String g(String k) => (d[k] as String? ?? '').trim();
      final firstTitle = entries.first.title;
      final thisTitle = title.isEmpty ? 'Untitled note' : title;
      if (firstTitle == thisTitle &&
          g('transcript') == transcript &&
          g('summary') == summary) {
        return false;
      }
    }
    entries.insert(
      0,
      DraftHistoryEntry(
        id: DateTime.now().toUtc().toIso8601String(),
        title: title.isEmpty ? 'Untitled note' : title,
        savedAt: DateTime.now().toUtc().toIso8601String(),
        draft: Map<String, dynamic>.from(draft),
      ),
    );
    while (entries.length > maxEntries) {
      entries.removeLast(); // oldest goes first; newest are kept
    }
    _notify();
    await _persist();
    return true;
  }

  Future<void> remove(String id) async {
    entries.removeWhere((e) => e.id == id);
    _notify();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _write(jsonEncode([
        for (final e in entries)
          {'id': e.id, 'title': e.title, 'savedAt': e.savedAt, 'draft': e.draft},
      ]));
      error = '';
    } catch (_) {
      error = 'Recent notes could not be saved.';
    }
    _notify();
  }
}

class DraftHistoryEntry {
  DraftHistoryEntry({
    required this.id,
    required this.title,
    required this.savedAt,
    required this.draft,
  });
  final String id, title, savedAt;
  final Map<String, dynamic> draft;
}
