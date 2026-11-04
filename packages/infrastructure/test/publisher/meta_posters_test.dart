import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
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

void main() {
  final image = Uri.parse(
    'https://ref.supabase.co/storage/v1/object/public/publisher-cards/g.jpg',
  );

  group('FacebookPagePoster', () {
    test(
      'posts the picture by URL with the words, the token in a header',
      () async {
        late http.Request seen;
        final poster = FacebookPagePoster(
          pageId: '123',
          token: 'secret-token',
          httpClient: MockClient((request) async {
            seen = request;
            return _json(<String, Object?>{'id': 'p1', 'post_id': '123_456'});
          }),
        );

        final outcome = await poster.post(
          text: 'هدف للهلال',
          image: const <int>[],
          imageUrl: image,
        );

        expect(outcome, isA<PosterPublished>());
        expect((outcome as PosterPublished).externalId, '123_456');
        expect(seen.url.path, '/$defaultGraphVersion/123/photos');
        expect(seen.headers['authorization'], 'Bearer secret-token');
        expect(seen.url.toString(), isNot(contains('secret-token')));
        expect(seen.bodyFields['url'], image.toString());
        expect(seen.bodyFields['message'], 'هدف للهلال');
      },
    );

    test('a correction with no picture is a text post on the feed', () async {
      late http.Request seen;
      final poster = FacebookPagePoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient((request) async {
          seen = request;
          return _json(<String, Object?>{'id': '123_789'});
        }),
      );

      final outcome = await poster.post(text: 'تصحيح: ألغى حكم الفيديو هدف');

      expect((outcome as PosterPublished).externalId, '123_789');
      expect(seen.url.path, '/$defaultGraphVersion/123/feed');
      expect(seen.bodyFields['message'], 'تصحيح: ألغى حكم الفيديو هدف');
      expect(seen.bodyFields.containsKey('url'), isFalse);
    });

    test('a rate limit is tried again later, nothing posted', () async {
      final poster = FacebookPagePoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient(
          (_) async => _json(<String, Object?>{
            'error': <String, Object?>{
              'code': 32,
              'message': 'Page request limit',
            },
          }, 400),
        ),
      );

      final outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterRetry>());
      expect((outcome as PosterRetry).after, const Duration(minutes: 10));
    });

    test('a refused token is given up', () async {
      final poster = FacebookPagePoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient(
          (_) async => _json(<String, Object?>{
            'error': <String, Object?>{'code': 190, 'message': 'Invalid OAuth'},
          }, 401),
        ),
      );

      final outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterRejected>());
    });

    test('a server error after the request arrived is uncertain', () async {
      final poster = FacebookPagePoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient((_) async => _json(<String, Object?>{}, 502)),
      );

      final outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterUncertain>());
    });

    test('a connection cut after sending is uncertain', () async {
      final poster = FacebookPagePoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient(
          (_) async => throw http.ClientException('reset'),
        ),
      );

      final outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterUncertain>());
    });

    test('a host that does not resolve was never reached', () async {
      final poster = FacebookPagePoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient(
          (_) async => throw http.ClientException('Failed host lookup: graph'),
        ),
      );

      final outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterRetry>());
    });

    test('reads the page name and a post\'s reactions', () async {
      final poster = FacebookPagePoster(
        pageId: '123',
        token: 't',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/123')) {
            return _json(<String, Object?>{'name': 'نُخبة'});
          }
          return _json(<String, Object?>{
            'reactions': <String, Object?>{
              'summary': <String, Object?>{'total_count': 41},
            },
            'comments': <String, Object?>{
              'summary': <String, Object?>{'total_count': 5},
            },
            'shares': <String, Object?>{'count': 2},
          });
        }),
      );

      expect(await poster.verify(), const Result<String>.ok('نُخبة'));
      final metrics = await poster.metrics('123_456');
      final value = (metrics as Ok<PostMetrics?>).value!;
      expect(value.reactions, 41);
      expect(value.comments, 5);
      expect(value.shares, 2);
    });
  });

  group('InstagramPoster', () {
    test(
      'makes a container from the URL, waits for it, publishes it',
      () async {
        final paths = <String>[];
        final poster = InstagramPoster(
          igUserId: '1784',
          token: 't',
          containerWait: Duration.zero,
          httpClient: MockClient((request) async {
            paths.add('${request.method} ${request.url.path}');
            if (request.url.path.endsWith('/1784/media')) {
              expect(request.bodyFields['image_url'], image.toString());
              return _json(<String, Object?>{'id': 'c9'});
            }
            if (request.url.path.endsWith('/c9')) {
              return _json(<String, Object?>{'status_code': 'FINISHED'});
            }
            return _json(<String, Object?>{'id': 'm7'});
          }),
        );

        final outcome = await poster.post(
          text: 'هدف',
          image: const <int>[],
          imageUrl: image,
        );

        expect((outcome as PosterPublished).externalId, 'm7');
        expect(paths, <String>[
          'POST /$defaultGraphVersion/1784/media',
          'GET /$defaultGraphVersion/c9',
          'POST /$defaultGraphVersion/1784/media_publish',
        ]);
      },
    );

    test('a cut before the container exists is safe to try again', () async {
      final poster = InstagramPoster(
        igUserId: '1784',
        token: 't',
        containerWait: Duration.zero,
        httpClient: MockClient(
          (_) async => throw http.ClientException('reset'),
        ),
      );

      final outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterRetry>());
    });

    test('takes no post without a picture, and asks nothing', () async {
      var asked = 0;
      final poster = InstagramPoster(
        igUserId: '1784',
        token: 't',
        httpClient: MockClient((_) async {
          asked++;
          return _json(<String, Object?>{});
        }),
      );

      final outcome = await poster.post(text: 'تصحيح');

      expect(outcome, isA<PosterRejected>());
      expect(asked, 0);
    });

    test('a container Instagram refuses is given up', () async {
      final poster = InstagramPoster(
        igUserId: '1784',
        token: 't',
        containerWait: Duration.zero,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/1784/media')) {
            return _json(<String, Object?>{'id': 'c9'});
          }
          return _json(<String, Object?>{'status_code': 'ERROR'});
        }),
      );

      final outcome = await poster.post(
        text: 'x',
        image: const <int>[],
        imageUrl: image,
      );

      expect(outcome, isA<PosterRejected>());
    });
  });

  group('metaPostersFromEnv', () {
    test('needs a token, and builds each platform with its own id', () {
      final client = MockClient((_) async => _json(<String, Object?>{}));

      expect(metaPostersFromEnv(const <String, String>{}, client), isEmpty);
      final both = metaPostersFromEnv(const <String, String>{
        'NUKHBA_META_PAGE_TOKEN': 't',
        'NUKHBA_META_PAGE_ID': '123',
        'NUKHBA_META_IG_USER_ID': '1784',
      }, client);
      expect(both.keys.toSet(), <PublishPlatform>{
        PublishPlatform.facebook,
        PublishPlatform.instagram,
      });
      final facebookOnly = metaPostersFromEnv(const <String, String>{
        'NUKHBA_META_PAGE_TOKEN': 't',
        'NUKHBA_META_PAGE_ID': '123',
      }, client);
      expect(facebookOnly.keys, <PublishPlatform>[PublishPlatform.facebook]);
    });
  });
}
