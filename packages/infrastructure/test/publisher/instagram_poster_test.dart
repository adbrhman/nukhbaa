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

  group('probe (script 211)', () {
    http.Client clientFor(
      List<String> paths, {
      Map<String, Object?>? quota,
      int quotaStatus = 200,
      String code = 'FINISHED',
    }) => MockClient((http.Request request) async {
      paths.add('${request.method} ${request.url.path}');
      final String path = request.url.path;
      if (path.endsWith('/123')) {
        return _json(_linkedPage());
      }
      if (path.endsWith('/content_publishing_limit')) {
        return _json(
          quota ??
              <String, Object?>{
                'data': <Object?>[
                  <String, Object?>{
                    'quota_usage': 3,
                    'config': <String, Object?>{'quota_total': 100},
                  },
                ],
              },
          quotaStatus,
        );
      }
      if (path.endsWith('/1784/media')) {
        return _json(<String, Object?>{'id': 'c9'});
      }
      if (path.endsWith('/c9')) {
        return _json(<String, Object?>{
          'status_code': code,
          'status': 'Error: bad picture',
        });
      }
      return _json(<String, Object?>{'id': 'm7'});
    });

    InstagramPoster posterOn(http.Client client) => InstagramPoster(
      pageId: '123',
      token: 't',
      containerWait: Duration.zero,
      httpClient: client,
    );

    test('a ready account passes and nothing is published', () async {
      final List<String> paths = <String>[];

      final Result<String> result = await posterOn(
        clientFor(paths),
      ).probe(image);

      expect(result, isA<Ok<String>>());
      expect((result as Ok<String>).value, contains('3/100'));
      expect(paths, contains('POST /v23.0/1784/media'));
      expect(paths.where((String p) => p.endsWith('media_publish')), isEmpty);
    });

    test('a token without the publish permission is told so', () async {
      final List<String> paths = <String>[];

      final Result<String> result = await posterOn(
        clientFor(
          paths,
          quotaStatus: 400,
          quota: <String, Object?>{
            'error': <String, Object?>{
              'message': 'permission denied',
              'code': 10,
            },
          },
        ),
      ).probe(image);

      expect(result, isA<Err<String>>());
      final AppError error = (result as Err<String>).error;
      expect(error.code, 'publisher.instagram_no_publish');
      expect(error.message, contains('permission denied'));
      expect(paths.where((String p) => p.endsWith('/1784/media')), isEmpty);
    });

    test(
      'a picture Instagram cannot take is refused with its reason',
      () async {
        final Result<String> result = await posterOn(
          clientFor(<String>[], code: 'ERROR'),
        ).probe(image);

        expect(result, isA<Err<String>>());
        final AppError error = (result as Err<String>).error;
        expect(error.code, 'publisher.instagram_picture');
        expect(error.message, contains('Error: bad picture'));
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
