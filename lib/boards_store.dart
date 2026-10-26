import 'dart:convert';
import 'package:http/http.dart' as http;

/// Web Firebase config for project voinoo. The web API key is public by
/// design; access control lives in the Firestore rules (owner-only boards,
/// counter-only anonymous writes). The Google OAuth web client ID identifies
/// this app to Google sign-in and is likewise public.
const defaultApiKey = String.fromEnvironment(
  'VOINO_FIREBASE_API_KEY',
  defaultValue: 'AIzaSyBhL3QPXjoYZDGg7J_tzWbN_BSnKZO9Zeo',
);
const defaultProjectId = String.fromEnvironment(
  'VOINO_FIREBASE_PROJECT',
  defaultValue: 'voinoo',
);
const defaultGoogleClientId = String.fromEnvironment(
  'VOINO_GOOGLE_CLIENT_ID',
  defaultValue: '816014640616-n6s7b9b492vnkpqtoarpig42vkbik6k1.apps.googleusercontent.com', // set after the console check; --dart-define can override
);

/// One saved board's listing entry (without the heavy data payload).
class BoardMeta {
  BoardMeta(this.id, this.title, this.updatedAt);
  final String id, title;
  final DateTime? updatedAt;
}

/// Saved boards in Firestore at users/{uid}/boards/{boardId}, owner-only per
/// the security rules. All calls need a fresh Firebase ID token from
/// [tokenProvider]; failures throw, callers decide how quietly to degrade.
class BoardsStore {
  BoardsStore({
    http.Client? client,
    required this.tokenProvider,
    this.projectId = defaultProjectId,
    this.apiKey = defaultApiKey,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Future<String?> Function() tokenProvider;
  final String projectId, apiKey;

  String get _base => 'projects/$projectId/databases/(default)/documents';

  Future<Map<String, String>> _headers() async {
    final t = await tokenProvider();
    if (t == null) throw StateError('signed out');
    return {'authorization': 'Bearer $t', 'content-type': 'application/json'};
  }

  String _boardPath(String uid, String id) => '$_base/users/$uid/boards/$id';

  static String _s(Map<String, dynamic> fields, String key) =>
      (fields[key] as Map?)?['stringValue'] as String? ?? '';

  Future<List<BoardMeta>> list(String uid) async {
    final r = await _client
        .get(
          Uri.parse(
            'https://firestore.googleapis.com/v1/$_base/users/$uid/boards?pageSize=50&key=$apiKey',
          ),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw StateError('list ${r.statusCode}');
    final docs =
        (jsonDecode(r.body) as Map<String, dynamic>)['documents'] as List? ??
        [];
    final out = <BoardMeta>[
      for (final d in docs)
        BoardMeta(
          (d['name'] as String).split('/').last,
          _s(d['fields'] as Map<String, dynamic>, 'title'),
          DateTime.tryParse(
            ((d['fields'] as Map)['updatedAt'] as Map?)?['timestampValue'] ??
                '',
          ),
        ),
    ];
    out.sort(
      (a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
    );
    return out;
  }

  Future<Map<String, dynamic>> load(String uid, String id) async {
    final r = await _client
        .get(
          Uri.parse(
            'https://firestore.googleapis.com/v1/${_boardPath(uid, id)}?key=$apiKey',
          ),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw StateError('load ${r.statusCode}');
    final fields =
        (jsonDecode(r.body) as Map<String, dynamic>)['fields']
            as Map<String, dynamic>;
    final data = jsonDecode(_s(fields, 'data'));
    if (data is! Map<String, dynamic>) throw const FormatException('bad board');
    return data;
  }

  Future<void> save(
    String uid,
    String id,
    String title,
    Map<String, dynamic> data,
  ) async {
    final r = await _client
        .patch(
          Uri.parse(
            'https://firestore.googleapis.com/v1/${_boardPath(uid, id)}?key=$apiKey',
          ),
          headers: await _headers(),
          body: jsonEncode({
            'fields': {
              'title': {'stringValue': title},
              'data': {'stringValue': jsonEncode(data)},
              'updatedAt': {
                'timestampValue': DateTime.now().toUtc().toIso8601String(),
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw StateError('save ${r.statusCode}');
  }

  Future<void> delete(String uid, String id) async {
    final r = await _client
        .delete(
          Uri.parse(
            'https://firestore.googleapis.com/v1/${_boardPath(uid, id)}?key=$apiKey',
          ),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw StateError('delete ${r.statusCode}');
  }
}
