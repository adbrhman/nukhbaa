import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2];

SupabaseStorageImageStore _store(
  http.Client client, {
  String key = 'sb_secret_abc',
}) => SupabaseStorageImageStore(
  storageUri: Uri.parse('https://ref123.supabase.co/storage/v1/'),
  serviceKey: key,
  httpClient: client,
);

void main() {
  test('a picture is put in the private bucket with the secret key', () async {
    final sent = <http.Request>[];
    final store = _store(
      MockClient((request) async {
        sent.add(request);
        return http.Response(jsonEncode({'Key': 'x'}), 200);
      }),
    );

    final result = await store.put('p/u/ab.jpg', _jpeg, 'image/jpeg');

    expect(result, isA<Ok<void>>());
    final request = sent.single;
    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      'https://ref123.supabase.co/storage/v1/object/support-images/p/u/ab.jpg',
    );
    expect(request.headers['apikey'], 'sb_secret_abc');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.headers['content-type'], 'image/jpeg');
    expect(request.bodyBytes, _jpeg);
  });

  test('a legacy service_role JWT goes in Authorization too', () async {
    final sent = <http.Request>[];
    await _store(
      MockClient((request) async {
        sent.add(request);
        return http.Response('{}', 200);
      }),
      key: 'eyJhbGciOiJIUzI1NiJ9.x.y',
    ).put('p/u/ab.jpg', _jpeg, 'image/jpeg');
    expect(
      sent.single.headers['authorization'],
      'Bearer eyJhbGciOiJIUzI1NiJ9.x.y',
    );
  });

  test('a picture is read back by its path', () async {
    final store = _store(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/storage/v1/object/support-images/legacy/c/8.jpg',
        );
        return http.Response.bytes(_jpeg, 200);
      }),
    );
    final read = await store.get('legacy/c/8.jpg');
    expect((read as Ok<List<int>>).value, _jpeg);
  });

  test('a refusal or a dead network is a transient error', () async {
    final refused = await _store(
      MockClient((_) async => http.Response('{}', 403)),
    ).put('p/u/ab.jpg', _jpeg, 'image/jpeg');
    final AppError error = (refused as Err<void>).error;
    expect(error.code, 'storage.refused');
    expect(error.kind, ErrorKind.transient);

    final down = await _store(
      MockClient((_) async => throw Exception('no route')),
    ).get('x.jpg');
    expect((down as Err<List<int>>).error.code, 'storage.unreachable');
  });

  test('support pictures are erased through the Storage API', () async {
    final sent = <http.Request>[];
    final store = _store(
      MockClient((request) async {
        sent.add(request);
        return http.Response('[]', 200);
      }),
    );
    final paths = <String>[for (int i = 0; i < 250; i++) 'p/u/$i.jpg'];

    final result = await store.erase(paths);

    expect(result, isA<Ok<void>>());
    expect(sent, hasLength(3));
    final first = sent.first;
    expect(first.method, 'DELETE');
    expect(
      first.url.toString(),
      'https://ref123.supabase.co/storage/v1/object/support-images',
    );
    expect(first.headers['apikey'], 'sb_secret_abc');
    expect(first.headers['content-type'], startsWith('application/json'));
    expect((jsonDecode(first.body) as Map)['prefixes'], hasLength(100));
    expect((jsonDecode(sent.last.body) as Map)['prefixes'], hasLength(50));
  });

  test('erasing nothing sends nothing; a refusal is transient', () async {
    final sent = <http.Request>[];
    final none = await _store(
      MockClient((request) async {
        sent.add(request);
        return http.Response('[]', 200);
      }),
    ).erase(const <String>[]);
    expect(none, isA<Ok<void>>());
    expect(sent, isEmpty);

    final refused = await _store(
      MockClient((_) async => http.Response('{}', 403)),
    ).erase(const <String>['p/u/1.jpg']);
    expect((refused as Err<void>).error.code, 'storage.refused');

    final down = await _store(
      MockClient((_) async => throw Exception('no route')),
    ).erase(const <String>['p/u/1.jpg']);
    expect((down as Err<void>).error.code, 'storage.unreachable');
  });

  test('without the secret key or the project there is no store', () {
    final client = MockClient((_) async => http.Response('', 200));
    expect(
      SupabaseStorageImageStore.fromEnv(const {
        'NUKHBA_SUPABASE_PROJECT_REF': 'ref123',
      }, client),
      isNull,
    );
    expect(
      SupabaseStorageImageStore.fromEnv(const {
        'NUKHBA_SUPABASE_SERVICE_KEY': 'sb_secret_abc',
      }, client),
      isNull,
    );
    expect(
      SupabaseStorageImageStore.fromEnv(const {
        'NUKHBA_SUPABASE_PROJECT_REF': 'ref123',
        'NUKHBA_SUPABASE_SERVICE_KEY': 'sb_secret_abc',
      }, client),
      isNotNull,
    );
  });
}
