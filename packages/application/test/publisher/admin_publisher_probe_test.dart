import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_publisher_store.dart';

const AuthenticatedUser _adminUser = AuthenticatedUser(
  userId: UserId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  role: PlatformRole.admin,
);

const AuthenticatedUser _playerUser = AuthenticatedUser(
  userId: UserId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  role: PlatformRole.user,
);

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 11, 5, 12);
}

final class _Renderer implements PublisherCardRenderer {
  final List<CardSpec> drawn = <CardSpec>[];
  Result<List<int>> answer = const Result.ok(<int>[0xFF, 0xD8, 0xFF]);

  @override
  Future<Result<List<int>>> render(CardSpec spec) async {
    drawn.add(spec);
    return answer;
  }
}

final class _Host implements PublisherCardHost {
  final Map<String, List<int>> files = <String, List<int>>{};

  @override
  Future<Result<void>> put(String path, List<int> bytes) async {
    files[path] = bytes;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<int>>> get(String path) async => Result.ok(files[path]!);

  @override
  Uri publicUrl(String path) => Uri.parse('https://cards.test/$path');
}

final class _Poster implements PlatformPoster, PublishProbe {
  Uri? asked;
  Result<String> answer = const Result.ok('ready');

  @override
  PublishPlatform get platform => PublishPlatform.instagram;

  @override
  Future<PosterOutcome> post({
    required String text,
    List<int>? image,
    Uri? imageUrl,
  }) async => const PosterRejected('never posted by the check');

  @override
  Future<Result<String>> verify() async => const Result.ok('nukhba');

  @override
  Future<Result<PostMetrics?>> metrics(String externalId) async =>
      const Result.ok(null);

  @override
  Future<Result<String>> probe(Uri imageUrl) async {
    asked = imageUrl;
    return answer;
  }
}

final class _PlainPoster implements PlatformPoster {
  @override
  PublishPlatform get platform => PublishPlatform.instagram;

  @override
  Future<PosterOutcome> post({
    required String text,
    List<int>? image,
    Uri? imageUrl,
  }) async => const PosterRejected('never');

  @override
  Future<Result<String>> verify() async => const Result.ok('nukhba');

  @override
  Future<Result<PostMetrics?>> metrics(String externalId) async =>
      const Result.ok(null);
}

void main() {
  late _Renderer renderer;
  late _Host host;
  late _Poster poster;

  AdminPublisher publisher({
    Map<PublishPlatform, PlatformPoster>? posters,
    bool withHost = true,
    bool withRenderer = true,
  }) => AdminPublisher(
    store: FakePublisherStore(),
    mode: PublisherMode.dryRun,
    posters:
        posters ??
        <PublishPlatform, PlatformPoster>{PublishPlatform.instagram: poster},
    clock: _Clock(),
    host: withHost ? host : null,
    renderer: withRenderer ? renderer : null,
  );

  setUp(() {
    renderer = _Renderer();
    host = _Host();
    poster = _Poster();
  });

  test('draws a test picture, keeps it and asks Instagram about it', () async {
    final Result<Result<String>> outer = await publisher().probeInstagram(
      principal: _adminUser,
    );

    expect(
      (outer as Ok<Result<String>>).value,
      const Result<String>.ok('ready'),
    );
    expect(renderer.drawn, hasLength(1));
    expect(host.files.keys, <String>[AdminPublisher.probePath]);
    expect(
      poster.asked,
      Uri.parse('https://cards.test/${AdminPublisher.probePath}'),
    );
  });

  test("Instagram's refusal comes back as the check's answer", () async {
    poster.answer = const Result.err(
      AppError.validation(
        'publisher.instagram_no_publish',
        'permission denied',
      ),
    );

    final Result<Result<String>> outer = await publisher().probeInstagram(
      principal: _adminUser,
    );

    final Result<String> inner = (outer as Ok<Result<String>>).value;
    expect((inner as Err<String>).error.code, 'publisher.instagram_no_publish');
  });

  test('a player may not run the check', () async {
    final Result<Result<String>> outer = await publisher().probeInstagram(
      principal: _playerUser,
    );

    expect(outer, isA<Err<Result<String>>>());
    expect(renderer.drawn, isEmpty);
    expect(poster.asked, isNull);
  });

  test('no Instagram account on the server is said plainly', () async {
    final Result<Result<String>> outer = await publisher(
      posters: <PublishPlatform, PlatformPoster>{},
    ).probeInstagram(principal: _adminUser);

    final Result<String> inner = (outer as Ok<Result<String>>).value;
    expect((inner as Err<String>).error.code, 'publisher.instagram_not_linked');
  });

  test('a poster that cannot be checked is said plainly', () async {
    final Result<Result<String>> outer = await publisher(
      posters: <PublishPlatform, PlatformPoster>{
        PublishPlatform.instagram: _PlainPoster(),
      },
    ).probeInstagram(principal: _adminUser);

    final Result<String> inner = (outer as Ok<Result<String>>).value;
    expect((inner as Err<String>).error.code, 'publisher.probe_unsupported');
  });

  test('a server with no host or renderer says what it lacks', () async {
    final Result<Result<String>> outer = await publisher(
      withHost: false,
    ).probeInstagram(principal: _adminUser);

    final Result<String> inner = (outer as Ok<Result<String>>).value;
    expect((inner as Err<String>).error.code, 'publisher.no_card_host');
    expect(poster.asked, isNull);
  });

  test('a picture that cannot be drawn stops the check', () async {
    renderer.answer = const Result.err(
      AppError.transient('publisher.render_failed', 'resvg missing'),
    );

    final Result<Result<String>> outer = await publisher().probeInstagram(
      principal: _adminUser,
    );

    final Result<String> inner = (outer as Ok<Result<String>>).value;
    expect((inner as Err<String>).error.code, 'publisher.render_failed');
    expect(poster.asked, isNull);
  });
}
