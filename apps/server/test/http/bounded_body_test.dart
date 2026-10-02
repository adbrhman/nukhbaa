import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/bounded_body.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/auth/refresh/index.dart' as refresh_route;
// ignore: always_use_package_imports
import '../../routes/me/avatar/index.dart' as avatar_route;

const String _userId = '00000000-0000-4000-8000-0000000000b1';
const int _chunkBytes = 16 * 1024;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

/// A request body that never ends: [_chunkBytes]-sized chunks for as long
/// as anyone listens. [pulled] counts the chunks handed out.
final class _EndlessBody {
  int pulled = 0;

  Stream<List<int>> stream() async* {
    final chunk = List<int>.filled(_chunkBytes, 0x20);
    while (true) {
      pulled++;
      yield chunk;
    }
  }
}

_MockRequestContext _wire({
  required Stream<List<int>> Function() body,
  Map<String, String> headers = const <String, String>{},
}) {
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.post);
  when(() => request.headers).thenReturn(headers);
  when(request.bytes).thenAnswer((_) => body());
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer(
    (_) => Future<CompositionRoot>.value(CompositionRoot.forTesting()),
  );
  when(() => context.read<AuthenticatedUser>()).thenReturn(
    const AuthenticatedUser(userId: UserId(_userId), role: PlatformRole.user),
  );
  return context;
}

Future<String?> _codeOf(Response response) async {
  final decoded = await response.json() as Map<Object?, Object?>;
  return decoded['code'] as String?;
}

void main() {
  group('readBoundedBytes', () {
    test('a body within the cap is read whole, across chunks', () async {
      final request = _MockRequest();
      when(request.bytes).thenAnswer(
        (_) => Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3],
        ]),
      );

      expect(await readBoundedBytes(request, 3), <int>[1, 2, 3]);
    });

    test('one byte over the cap is refused', () async {
      final request = _MockRequest();
      when(request.bytes).thenAnswer(
        (_) => Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3],
        ]),
      );

      expect(await readBoundedBytes(request, 2), isNull);
    });
  });

  group('the routes stop reading at the cap', () {
    test('an endless JSON body to /auth/refresh is refused with 400 '
        'request.body_too_large', () async {
      final body = _EndlessBody();

      final response = await refresh_route
          .onRequest(_wire(body: body.stream))
          .timeout(const Duration(seconds: 10));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(await _codeOf(response), 'request.body_too_large');
      expect(
        body.pulled,
        lessThanOrEqualTo(maxJsonBodyBytes ~/ _chunkBytes + 2),
      );
    });

    test('a JSON body under the cap still reaches field validation', () async {
      final response = await refresh_route.onRequest(
        _wire(
          body: () => Stream<List<int>>.fromIterable(<List<int>>[
            utf8.encode('{"refresh'),
            utf8.encode('_token": 7}'),
          ]),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(await _codeOf(response), 'request.field_missing');
    });

    test('an endless picture to /me/avatar is refused as too large', () async {
      final body = _EndlessBody();

      final response = await avatar_route
          .onRequest(
            _wire(
              body: body.stream,
              headers: const <String, String>{
                HttpHeaders.contentTypeHeader: 'image/png',
              },
            ),
          )
          .timeout(const Duration(seconds: 10));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(await _codeOf(response), 'identity.avatar_too_large');
      expect(
        body.pulled,
        lessThanOrEqualTo(User.maxAvatarBytes ~/ _chunkBytes + 2),
      );
    });
  });
}
