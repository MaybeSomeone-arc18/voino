import 'dart:async';

import 'boards_store.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Google sign-in + Firebase Auth (REST, no Firebase SDK).
///
/// Flow: the google_sign_in plugin gets a Google ID token, which we exchange
/// for a Firebase ID token at identitytoolkit signInWithIdp. The Firebase
/// token authorizes Firestore REST calls (rules see request.auth.uid). It
/// expires after an hour, so we keep the refresh token in secure storage and
/// mint a fresh ID token on demand. Signing out clears both.
class VoinoAuth extends ChangeNotifier {
  VoinoAuth({
    http.Client? client,
    FlutterSecureStorage? storage,
    this.apiKey = defaultApiKey,
    this.googleClientId = defaultGoogleClientId,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;
  final String apiKey, googleClientId;

  static const _refreshKey = 'voino_firebase_refresh_v1';

  bool ready = false, busy = false;
  String? uid, email;
  String? _idToken, _refreshToken;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  String error = '';

  bool get signedIn => uid != null;

  /// Restores a previous session from the stored refresh token, if any.
  Future<void> init() async {
    try {
      _refreshToken = await _storage.read(key: _refreshKey);
      if (_refreshToken != null) await _refresh();
    } catch (_) {
      _refreshToken = null; // treat a bad/expired stored token as signed out
    }
    ready = true;
    notifyListeners();
  }

  Future<bool> signIn() async {
    busy = true;
    error = '';
    notifyListeners();
    try {
      await GoogleSignIn.instance.initialize(clientId: googleClientId);
      final account = await GoogleSignIn.instance.authenticate();
      final googleToken = account.authentication.idToken;
      if (googleToken == null) throw StateError('Google returned no ID token');
      await _exchange(googleToken);
      busy = false;
      notifyListeners();
      return true;
    } on GoogleSignInException {
      busy = false; // user closed the chooser - not an error worth showing
      notifyListeners();
      return false;
    } catch (e) {
      busy = false;
      error = 'Sign-in did not complete. Try again.';
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    uid = email = _idToken = _refreshToken = null;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
    notifyListeners();
  }

  /// A Firebase ID token valid for at least the next minute, or null when
  /// signed out / unreachable (callers fall back to offline behaviour).
  Future<String?> idToken() async {
    if (_refreshToken == null) return null;
    if (DateTime.now().isBefore(_expiresAt.subtract(const Duration(minutes: 1)))) {
      return _idToken;
    }
    try {
      await _refresh();
      return _idToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> _exchange(String googleIdToken) async {
    final r = await _client
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$apiKey',
          ),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'postBody': 'id_token=$googleIdToken&providerId=google.com',
            'requestUri': 'https://voino.vercel.app',
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw StateError('signInWithIdp ${r.statusCode}');
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    uid = d['localId'] as String?;
    email = d['email'] as String?;
    _idToken = d['idToken'] as String?;
    _refreshToken = d['refreshToken'] as String?;
    _expiresAt = DateTime.now().add(
      Duration(seconds: int.tryParse('${d['expiresIn']}') ?? 3600),
    );
    if (uid == null || _refreshToken == null) {
      throw StateError('incomplete sign-in response');
    }
    try {
      await _storage.write(key: _refreshKey, value: _refreshToken);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    final r = await _client
        .post(
          Uri.parse(
            'https://securetoken.googleapis.com/v1/token?key=$apiKey',
          ),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'grant_type': 'refresh_token',
            'refresh_token': _refreshToken,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw StateError('refresh ${r.statusCode}');
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    uid = d['user_id'] as String? ?? uid;
    _idToken = d['id_token'] as String?;
    _refreshToken = d['refresh_token'] as String? ?? _refreshToken;
    _expiresAt = DateTime.now().add(
      Duration(seconds: int.tryParse('${d['expires_in']}') ?? 3600),
    );
    try {
      await _storage.write(key: _refreshKey, value: _refreshToken);
    } catch (_) {}
  }
}
