import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

Map<String, Object?> _linkedPage() => <String, Object?>{
  'id': '123',
  'instagram_business_account': <String, Object?>{
    'id': '1784',
    'username': 'nukhba_app',
  },
};

void main() {
  final Uri image = Uri.parse(
    'https://ref.supabase.co/storage/v1/object/public/publisher-cards/g.jpg',
  );

  group('the account', () {
    test('is the one the page is linked to, asked once', () async {
      final List<String> paths = <String>[];
      final InstagramPoster poster = InstagramPoster(
        pageId: '123',
        token: 't',
        containerWait: Duration.zero,
        httpClient: MockClient((http.Request request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/123')) {
            expect(
              request.url.queryParameters['fields'],
              'instagram_business_account{id,username}',
            );
            return _json(_linkedPage());
          }
          if (request.url.path.endsWith('/1784/media')) {
            return _json(<String, Object?>{'id': 'c9'});
          }
          if (request.url.path.endsWith('/c9')) {
            return _json(<String, Object?>{'status_code': 'FINISHED'});
          }
          return _json(<String, Object?>{'id': 'm7'});
        }),
      );

      final PosterOutcome first = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );
      await poster.post(text: 'y', image: const <int>[], imageUrl: image);

      expect((first as PosterPublished).externalId, 'm7');
      expect(paths.where((String p) => p.endsWith('/v23.0/123')), hasLength(1));
      expect(
        paths.where((String p) => p.endsWith('/1784/media_publish')),
        hasLength(2),
      );
      expect(await poster.verify(), const Result<String>.ok('nukhba_app'));
    });

    test('a configured id is used and the page is never asked', () async {
      final List<String> paths = <String>[];
      final InstagramPoster poster = InstagramPoster(
        igUserId: '1784',
        pageId: '123',
        token: 't',
        containerWait: Duration.zero,
        httpClient: MockClient((http.Request request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/1784/media')) {
            return _json(<String, Object?>{'id': 'c9'});
          }
          if (request.url.path.endsWith('/c9')) {
            return _json(<String, Object?>{'status_code': 'FINISHED'});
          }
          return _json(<String, Object?>{'id': 'm7'});
        }),
      );

      await poster.post(text: 'x', image: const <int>[], imageUrl: image);

      expect(paths.any((String p) => p.endsWith('/123')), isFalse);
    });

    test(
      'a page linked to no Instagram account is given up, and said',
      () async {
        final InstagramPoster poster = InstagramPoster(
          pageId: '123',
          token: 't',
          httpClient: MockClient(
            (_) async => _json(<String, Object?>{'id': '123'}),
          ),
        );

        final PosterOutcome outcome = await poster.post(
          text: 'x',
          image: const <int>[],
          imageUrl: image,
        );

        expect(outcome, isA<PosterRejected>());
        expect((outcome as PosterRejected).reason, 'instagram_not_linked');
        expect(await poster.verify(), isA<Err<String>>());
      },
    );

    test('Meta not answering about the page is tried again later', () async {
      final InstagramPoster poster = InstagramPoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient(
          (_) async => throw http.ClientException('reset'),
        ),
      );

      final PosterOutcome outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterRetry>());
    });
  });

  group('a container not ready', () {
    test('after every look is tried again later, never published', () async {
      final List<String> paths = <String>[];
      final InstagramPoster poster = InstagramPoster(
        igUserId: '1784',
        token: 't',
        containerWait: Duration.zero,
        containerLooks: 3,
        httpClient: MockClient((http.Request request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/1784/media')) {
            return _json(<String, Object?>{'id': 'c9'});
          }
          return _json(<String, Object?>{'status_code': 'IN_PROGRESS'});
        }),
      );

      final PosterOutcome outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterRetry>());
      expect((outcome as PosterRetry).reason, 'container_in_progress');
      expect(paths.where((String p) => p.endsWith('/c9')), hasLength(3));
      expect(paths.any((String p) => p.endsWith('media_publish')), isFalse);
    });

    test(
      'refused at publishing with 9007 is tried again, not given up',
      () async {
        final InstagramPoster poster = InstagramPoster(
          igUserId: '1784',
          token: 't',
          containerWait: Duration.zero,
          httpClient: MockClient((http.Request request) async {
            if (request.url.path.endsWith('/1784/media')) {
              return _json(<String, Object?>{'id': 'c9'});
            }
            if (request.url.path.endsWith('/c9')) {
              return _json(<String, Object?>{'status_code': 'FINISHED'});
            }
            return _json(<String, Object?>{
              'error': <String, Object?>{
                'code': 9007,
                'message': 'Media ID is not available',
              },
            }, 400);
          }),
        );

        final PosterOutcome outcome = await poster.post(
          text: 'x',
          image: const <int>[],
          imageUrl: image,
        );

        expect(outcome, isA<PosterRetry>());
        expect((outcome as PosterRetry).reason, 'container_not_ready');
      },
    );
  });

  test('metaPostersFromEnv builds Instagram from the page alone', () {
    final http.Client client = MockClient(
      (_) async => _json(<String, Object?>{}),
    );

    final posters = metaPostersFromEnv(const <String, String>{
      'NUKHBA_META_PAGE_TOKEN': 't',
      'NUKHBA_META_PAGE_ID': '123',
    }, client);
    final idOnly = metaPostersFromEnv(const <String, String>{
      'NUKHBA_META_PAGE_TOKEN': 't',
      'NUKHBA_META_IG_USER_ID': '1784',
    }, client);

    expect(posters.keys.map((p) => p.wire).toSet(), <String>{
      'facebook',
      'instagram',
    });
    expect(idOnly.keys.map((p) => p.wire).toList(), <String>['instagram']);
  });
}
