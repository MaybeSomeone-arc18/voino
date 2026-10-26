import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voino/auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestFlutterSecureStoragePlatform storagePlatform;

  setUp(() {
    storagePlatform = TestFlutterSecureStoragePlatform({});
    FlutterSecureStoragePlatform.instance = storagePlatform;
  });

  VoinoAuth make(MockClient client) => VoinoAuth(
    client: client,
    storage: const FlutterSecureStorage(),
    apiKey: 'test-key',
    googleClientId: 'test-client',
  );

  Future<void> seedRefreshToken() async {
    await const FlutterSecureStorage().write(
      key: 'voino_firebase_refresh_v1',
      value: 'rt-1',
    );
  }

  test('init restores a session from the stored refresh token', () async {
    await seedRefreshToken();
    final bodies = <String>[];
    final auth = make(
      MockClient((req) async {
        bodies.add((req as http.Request).body);
        expect(req.url.host, 'securetoken.googleapis.com');
        return http.Response(
          jsonEncode({
            'id_token': 'fb-id-1',
            'refresh_token': 'rt-2',
            'user_id': 'uid-1',
            'expires_in': '3600',
          }),
          200,
        );
      }),
    );
    await auth.init();
    expect(auth.ready, isTrue);
    expect(auth.signedIn, isTrue);
    expect(auth.uid, 'uid-1');
    // Stored refresh token rotates to the newest value.
    expect(
      await const FlutterSecureStorage().read(key: 'voino_firebase_refresh_v1'),
      'rt-2',
    );
    // idToken() is fresh for an hour, so no extra refresh call.
    expect(await auth.idToken(), 'fb-id-1');
    expect(bodies, hasLength(1));
    expect(jsonDecode(bodies.single)['refresh_token'], 'rt-1');
    expect(jsonDecode(bodies.single)['grant_type'], 'refresh_token');
  });

  test('init without a stored token stays signed out without network', () async {
    final auth = make(
      MockClient((req) async => throw StateError('must not be called')),
    );
    await auth.init();
    expect(auth.ready, isTrue);
    expect(auth.signedIn, isFalse);
    expect(await auth.idToken(), isNull);
  });

  test('init with a failing refresh falls back to signed out', () async {
    await seedRefreshToken();
    final auth = make(MockClient((req) async => http.Response('bad', 400)));
    await auth.init();
    expect(auth.ready, isTrue);
    expect(auth.signedIn, isFalse);
    expect(await auth.idToken(), isNull);
  });
}
