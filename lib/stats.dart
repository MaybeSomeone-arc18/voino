import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Privacy-safe usage counters.
///
/// What is counted: listening sessions started, boards created, devices active
/// per day, and returning devices. What is sent: anonymous "+1" increments
/// only. The device id, transcript, notes, titles and board content NEVER
/// leave the device through this path; the increments carry no identity.
///
/// The store is the project's own Firestore database (`voinoo`), written
/// through its REST API with aggregate documents only:
///   counters/all              {sessions, boards, devices, returning}
///   counters/daily_YYYY-MM-DD {sessions, boards, devices, returning}  (UTC day)
/// Read access stays owner-only; he reads the numbers in the Firebase console.
///
/// The counter is disabled (a silent no-op) until the web API key is set with
/// --dart-define=VOINO_FIREBASE_API_KEY=... or edited into [defaultApiKey].
/// The key is not a secret (Firebase web keys are public by design; the
/// Firestore rules are what restrict writes to counter-shaped increments).
const defaultProjectId = String.fromEnvironment(
  'VOINO_FIREBASE_PROJECT',
  defaultValue: 'voinoo',
);
const defaultApiKey = String.fromEnvironment('VOINO_FIREBASE_API_KEY');

typedef StatsReader = Future<String?> Function(String key);
typedef StatsWriter = Future<void> Function(String key, String value);

class Stats {
  Stats({
    http.Client? client,
    StatsReader? read,
    StatsWriter? write,
    this.projectId = defaultProjectId,
    this.apiKey = defaultApiKey,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _read = read ?? ((k) => const FlutterSecureStorage().read(key: k)),
       _write =
           write ??
           ((k, v) => const FlutterSecureStorage().write(key: k, value: v)),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final StatsReader _read;
  final StatsWriter _write;
  final String projectId, apiKey;
  final DateTime Function() _now;

  static const _idKey = 'stats_device_id';
  static const _firstDayKey = 'stats_first_day';
  static const _lastDayKey = 'stats_last_day';

  bool get enabled => projectId.isNotEmpty && apiKey.isNotEmpty;

  String _today() => _now().toUtc().toIso8601String().substring(0, 10);

  String _newId() {
    final r = DateTime.now().microsecondsSinceEpoch;
    var x = r ^ (r << 13) ^ 0x9e3779b9;
    String four() {
      x ^= x << 13;
      x ^= x >> 7;
      x ^= x << 17;
      return (x & 0xffff).toRadixString(16).padLeft(4, '0');
    }

    return '${four()}${four()}-${four()}-${four()}-${four()}-${four()}${four()}${four()}';
  }

  /// Loads or creates the anonymous device id, then counts the device as
  /// active today (and as returning if it was first seen on an earlier day).
  Future<void> appOpened() async {
    String? id;
    try {
      id = await _read(_idKey);
    } catch (_) {}
    if (id == null || id.isEmpty) {
      id = _newId();
      try {
        await _write(_idKey, id);
      } catch (_) {}
    }
    final today = _today();
    String? firstDay, lastDay;
    try {
      firstDay = await _read(_firstDayKey);
      lastDay = await _read(_lastDayKey);
    } catch (_) {}
    if (firstDay == null || firstDay.isEmpty) {
      firstDay = today;
      try {
        await _write(_firstDayKey, today);
      } catch (_) {}
    }
    if (lastDay == today) return; // already counted today
    try {
      await _write(_lastDayKey, today);
    } catch (_) {}
    await _bump(devices: 1, returning: firstDay == today ? 0 : 1);
  }

  Future<void> sessionStarted() => _bump(sessions: 1);

  Future<void> boardCreated() => _bump(boards: 1);

  /// Fire-and-forget increment of the aggregate documents. Any failure
  /// (offline, rules not yet opened, key not set) is swallowed: counting must
  /// never break listening.
  Future<void> _bump({
    int sessions = 0,
    int boards = 0,
    int devices = 0,
    int returning = 0,
  }) async {
    if (!enabled) return;
    final fields = <String, int>{
      if (sessions > 0) 'sessions': sessions,
      if (boards > 0) 'boards': boards,
      if (devices > 0) 'devices': devices,
      if (returning > 0) 'returning': returning,
    };
    if (fields.isEmpty) return;
    final base = 'projects/$projectId/databases/(default)/documents';
    Map<String, dynamic> transform(String doc) => {
      'transform': {
        'document': '$base/counters/$doc',
        'fieldTransforms': [
          for (final e in fields.entries)
            {
              'fieldPath': e.key,
              'increment': {'integerValue': '${e.value}'},
            },
        ],
      },
    };
    try {
      await _client
          .post(
            Uri.parse(
              'https://firestore.googleapis.com/v1/$base:commit?key=$apiKey',
            ),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'writes': [transform('all'), transform('daily_${_today()}')],
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}
