import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'board.dart';

/// One device-local recovery draft, not history or cloud backup.
class LocalDraft extends ChangeNotifier {
  LocalDraft({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read =
           read ??
           (() => const FlutterSecureStorage().read(key: 'voino_draft_v1')),
       _write =
           write ??
           ((s) => const FlutterSecureStorage().write(
             key: 'voino_draft_v1',
             value: s,
           ));
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  bool ready = false, saved = false, _disposed = false;
  String error = '';
  String? _pending;
  int _revision = 0;
  Timer? _timer;
  Future<void> _queue = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      final raw = await _read();
      Map<String, dynamic>? draft;
      if (raw != null && raw.isNotEmpty) {
        final value = jsonDecode(raw);
        if (value is! Map<String, dynamic> ||
            value['draftVersion'] != 1 ||
            value['title'] is! String ||
            value['transcript'] is! String ||
            parseBoardJson(raw) == null) {
          throw const FormatException('Invalid local draft');
        }
        draft = value;
      }
      ready = true;
      saved = draft != null;
      _notify();
      return draft;
    } catch (_) {
      error = 'Local draft could not be read. Copy notes before closing.';
      _notify();
      return null; // Do not overwrite a draft we could not read.
    }
  }

  void changed(Map<String, dynamic> draft) {
    if (!ready || _disposed) return;
    _revision++;
    _pending = jsonEncode({...draft, 'draftVersion': 1});
    saved = false;
    error = '';
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), flush);
    _notify();
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final value = _pending;
    final revision = _revision;
    if (value == null) return _queue;
    _pending = null;
    _queue = _queue.then((_) async {
      try {
        await _write(value);
        saved = revision == _revision && _pending == null;
        error = '';
      } catch (_) {
        saved = false;
        error = 'Local save failed. Copy notes before closing.';
        if (revision == _revision) _pending ??= value;
      }
      _notify();
    });
    return _queue;
  }

  @override
  void dispose() {
    flush();
    _disposed = true;
    super.dispose();
  }
}
