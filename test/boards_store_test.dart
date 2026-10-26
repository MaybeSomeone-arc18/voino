import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voino/boards_store.dart';

void main() {
  String? token;
  Future<String?> provider() async => token;

  test('list maps documents and sorts newest first', () async {
    token = 'tok';
    http.Request? seen;
    final client = MockClient((req) async {
      seen = req as http.Request;
      return http.Response(
        jsonEncode({
          'documents': [
            {
              'name': 'projects/p/databases/(default)/documents/users/u1/boards/b1',
              'fields': {
                'title': {'stringValue': 'Old'},
                'updatedAt': {'timestampValue': '2026-10-20T10:00:00Z'},
              },
            },
            {
              'name': 'projects/p/databases/(default)/documents/users/u1/boards/b2',
              'fields': {
                'title': {'stringValue': 'New'},
                'updatedAt': {'timestampValue': '2026-10-25T10:00:00Z'},
              },
            },
          ],
        }),
        200,
      );
    });
    final store = BoardsStore(client: client, tokenProvider: provider);
    final boards = await store.list('u1');
    expect(boards.map((b) => b.id), ['b2', 'b1']);
    expect(boards.first.title, 'New');
    expect(seen!.headers['authorization'], 'Bearer tok');
    expect(seen!.url.path, contains('users/u1/boards'));
    expect(seen!.url.queryParameters['pageSize'], '50');
  });

  test('load decodes the board data payload', () async {
    token = 'tok';
    final client = MockClient((req) async {
      expect(req.url.path, contains('users/u1/boards/b7'));
      return http.Response(
        jsonEncode({
          'fields': {
            'title': {'stringValue': 'Ideas'},
            'data': {
              'stringValue': jsonEncode({
                'title': 'Ideas',
                'notes': [
                  {'id': 'n1', 'text': 'hello'},
                ],
              }),
            },
          },
        }),
        200,
      );
    });
    final data = await BoardsStore(
      client: client,
      tokenProvider: provider,
    ).load('u1', 'b7');
    expect(data['title'], 'Ideas');
    expect((data['notes'] as List).single['id'], 'n1');
  });

  test('save patches title, data and updatedAt', () async {
    token = 'tok';
    http.Request? seen;
    final client = MockClient((req) async {
      seen = req as http.Request;
      return http.Response('{}', 200);
    });
    await BoardsStore(client: client, tokenProvider: provider).save(
      'u1',
      'b1',
      'My board',
      {'title': 'My board', 'notes': []},
    );
    expect(seen!.method, 'PATCH');
    expect(seen!.url.path, contains('users/u1/boards/b1'));
    final fields = (jsonDecode(seen!.body) as Map)['fields'] as Map;
    expect((fields['title'] as Map)['stringValue'], 'My board');
    expect(
      jsonDecode((fields['data'] as Map)['stringValue'] as String)['title'],
      'My board',
    );
    expect((fields['updatedAt'] as Map)['timestampValue'], isNotEmpty);
  });

  test('delete removes the board document', () async {
    token = 'tok';
    http.Request? seen;
    final client = MockClient((req) async {
      seen = req as http.Request;
      return http.Response('', 200);
    });
    await BoardsStore(
      client: client,
      tokenProvider: provider,
    ).delete('u1', 'b9');
    expect(seen!.method, 'DELETE');
    expect(seen!.url.path, contains('users/u1/boards/b9'));
  });

  test('non-200 responses throw and signed-out token fails fast', () async {
    token = 'tok';
    final failing = BoardsStore(
      client: MockClient((req) async => http.Response('nope', 403)),
      tokenProvider: provider,
    );
    expect(() => failing.list('u1'), throwsStateError);
    token = null;
    expect(() => failing.list('u1'), throwsStateError);
  });
}
