import 'dart:async';
import 'package:flutter/foundation.dart';

/// Keeps user intent separate from the platform's short recognizer sessions.
/// Restart gaps are visible; this is not gapless audio recording.
class ListeningSession extends ChangeNotifier {
  ListeningSession({
    required this.startEngine,
    required this.stopEngine,
    required this.onWords,
    this.restartDelay = const Duration(milliseconds: 900),
  });
  final Future<void> Function(void Function(String)) startEngine;
  final Future<void> Function() stopEngine;
  final void Function(String words, bool newSession) onWords;
  final Duration restartDelay;
  bool requested = false, active = false, _starting = false, _disposed = false;
  String message = '';
  int _token = 0, _failedStarts = 0;
  Timer? _restart, _startWatch;
  bool _acceptResults = false, _stopping = false, _closingOld = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (requested || _disposed || _stopping) return;
    requested = true;
    _failedStarts = 0;
    await _begin();
  }

  Future<void> _begin() async {
    if (!requested || _starting || _disposed) return;
    _starting = true;
    active = false;
    message = 'Connecting microphone...';
    final token = ++_token;
    var first = true;
    _acceptResults = true;
    _notify();
    try {
      await startEngine((words) {
        if (!_acceptResults || token != _token || _disposed) return;
        onWords(words, first);
        if (words.trim().isNotEmpty) first = false;
      });
      if (requested && token == _token && !active) {
        _startWatch?.cancel();
        _startWatch = Timer(const Duration(seconds: 3), () {
          if (requested && !active && token == _token) {
            error('microphone_unavailable');
          }
        });
      }
      if (!requested || token != _token || _disposed) {
        await stopEngine();
      }
    } catch (_) {
      if (requested && token == _token) {
        _failedStarts++;
        if (_failedStarts >= 2) {
          requested = false;
          message =
              'Microphone could not restart. Tap to try again or type instead.';
        } else {
          _queueRestart();
        }
      }
    } finally {
      _starting = false;
      _notify();
    }
  }

  void status(String status) {
    if (!requested || _disposed || _closingOld) return;
    if (status == 'listening') {
      _startWatch?.cancel();
      active = true;
      _failedStarts = 0;
      message = 'Listening · tap to stop';
      _restart?.cancel();
      _restart = null;
    } else if (status == 'done' || status == 'notListening') {
      active = false;
      _queueRestart();
    }
    _notify();
  }

  void error(String error) {
    if (!requested || _disposed) return;
    active = false;
    // Silence/no-match can end a normal session. Other errors need attention.
    if (error == 'error_no_match' ||
        error == 'error_speech_timeout' ||
        error == 'no-speech' ||
        error == 'error_no_speech') {
      _queueRestart();
    } else {
      requested = false;
      _acceptResults = false;
      _startWatch?.cancel();
      _token++;
      _restart?.cancel();
      _restart = null;
      message = 'Speech stopped: $error. Tap to try again or type instead.';
      stopEngine().catchError((_) {});
    }
    _notify();
  }

  void _queueRestart() {
    if (!requested || _disposed || _restart != null) return;
    _startWatch?.cancel();
    message = 'Reconnecting microphone... · tap to stop';
    _restart = Timer(restartDelay, () async {
      _restart = null;
      if (!requested || _disposed) return;
      _closingOld = true;
      try {
        await stopEngine();
      } catch (_) {}
      _closingOld = false;
      if (requested && !_disposed) await _begin();
    });
  }

  Future<void> stop({String note = ''}) async {
    _stopping = true;
    requested = false;
    active = false;
    _startWatch?.cancel();
    _restart?.cancel();
    _restart = null;
    message = note;
    _notify();
    try {
      await stopEngine();
    } catch (_) {}
    _acceptResults = false;
    _token++;
    _stopping = false;
  }

  @override
  void dispose() {
    requested = false;
    _disposed = true;
    _token++;
    _restart?.cancel();
    _startWatch?.cancel();
    super.dispose();
  }
}
