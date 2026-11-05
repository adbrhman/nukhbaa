import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_publisher_store.dart';

final class _Board implements LiveScoreBoard {
  final Map<String, LiveScore> scores = <String, LiveScore>{};

  void show(String fixtureId, int home, int away, DateTime at, {int? minute}) {
    scores[fixtureId] = LiveScore(
      homeGoals: home,
      awayGoals: away,
      finished: false,
      updatedAt: at,
      minute: minute,
    );
  }

  @override
  void put(Map<String, LiveScore> scores) => this.scores.addAll(scores);

  @override
  void remove(Iterable<String> fixtureIds) => fixtureIds.forEach(scores.remove);

  @override
  Map<String, LiveScore> read(Iterable<String> fixtureIds) =>
      <String, LiveScore>{
        for (final id in fixtureIds)
          if (scores[id] case final score?) id: score,
      };
}

final class _Renderer implements PublisherCardRenderer {
  final List<CardSpec> drawn = <CardSpec>[];

  @override
  Future<Result<List<int>>> render(CardSpec spec) async {
    drawn.add(spec);
    return const Result.ok(<int>[0xFF, 0xD8, 0xFF]);
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
  Future<Result<List<int>>> get(String path) async {
    final bytes = files[path];
    return bytes == null
        ? const Result.err(AppError.transient('storage.refused', 'missing'))
        : Result.ok(bytes);
  }

  @override
  Uri publicUrl(String path) => Uri.parse('https://cards.test/$path');
}

final class _Poster implements PlatformPoster {
  _Poster(this.platform);

  @override
  final PublishPlatform platform;

  final List<String> sent = <String>[];
  final List<bool> withPicture = <bool>[];
  PosterOutcome next = const PosterPublished('ext-1');

  @override
  Future<PosterOutcome> post({
    required String text,
    List<int>? image,
    Uri? imageUrl,
  }) async {
    sent.add(text);
    withPicture.add(imageUrl != null);
    return next;
  }

  @override
  Future<Result<String>> verify() async => const Result.ok('Nukhba');

  @override
  Future<Result<PostMetrics?>> metrics(String externalId) async =>
      const Result.ok(PostMetrics(reactions: 7));
}

final class _Crests implements ClubCrestSource {
  final Map<String, List<int>> files = <String, List<int>>{};

  @override
  Future<List<int>?> crestOf(String clubName) async => files[clubName];
}

final class _Details implements LiveGoalDetails {
  List<MatchEvent>? events;
  int asked = 0;

  @override
  Future<Result<List<MatchEvent>?>> eventsOf({
    required String fixtureId,
    required String leagueName,
    required DateTime kickoffAt,
  }) async {
    asked++;
    return Result.ok(events);
  }
}

void main() {
  const fixture = 'fx-1';
  final kickoff = DateTime.utc(2026, 11, 7, 17);
  late FakePublisherStore store;
  late _Board board;
  late _Renderer renderer;
  late _Host host;
  late _Poster facebook;
  late _Poster instagram;
  late _Details details;

  PublisherTick tick({
    PublisherMode mode = PublisherMode.on,
    bool askDetails = false,
    ClubCrestSource? crests,
  }) => PublisherTick(
    store: store,
    board: board,
    mode: mode,
    posters: <PublishPlatform, PlatformPoster>{
      PublishPlatform.facebook: facebook,
      PublishPlatform.instagram: instagram,
    },
    renderer: renderer,
    host: host,
    details: askDetails ? details : null,
    crests: crests,
  );

  DateTime at(int minutes) => kickoff.add(Duration(minutes: minutes));

  setUp(() {
    store = FakePublisherStore();
    board = _Board();
    renderer = _Renderer();
    host = _Host();
    facebook = _Poster(PublishPlatform.facebook);
    instagram = _Poster(PublishPlatform.instagram);
    details = _Details();
    store.coverage[fixture] = FakeCoverage(
      fixtureId: fixture,
      homeName: 'الهلال',
      awayName: 'النصر',
      leagueName: 'دوري روشن السعودي',
      kickoffAt: kickoff,
      addedAt: kickoff.subtract(const Duration(hours: 2)),
      homeTeamId: 'team-h',
      awayTeamId: 'team-a',
    );
    for (final platform in PublishPlatform.values) {
      store.enable(platform);
    }
  });

  group('a goal', () {
    test(
      'is kept pending when the feed shows it, never posted at once',
      () async {
        board.show(fixture, 1, 0, at(12), minute: 11);

        final report = await tick()(now: at(12));

        expect((report as Ok<PublisherTickReport>).value.seen, 1);
        expect(store.goals.single.state, StoredGoalState.pending);
        expect(store.goals.single.step.key, 'h1');
        expect(store.posts, isEmpty);
        expect(facebook.sent, isEmpty);
      },
    );

    test(
      'once it stood its hold, is confirmed with one post per platform',
      () async {
        details.events = const <MatchEvent>[
          MatchEvent(
            minute: '11',
            kind: MatchEventKind.goal,
            home: true,
            player: 'سالم الدوسري',
          ),
        ];
        board.show(fixture, 1, 0, at(12), minute: 11);
        await tick(askDetails: true)(now: at(12));

        await tick(askDetails: true)(now: at(15));

        final goal = store.goals.single;
        expect(goal.state, StoredGoalState.confirmed);
        expect(goal.scorer, 'سالم الدوسري');
        expect(goal.moment, GoalMoment.opener);
        expect(
          store.posts.map((p) => p.post.platform).toSet(),
          <PublishPlatform>{
            PublishPlatform.facebook,
            PublishPlatform.instagram,
            PublishPlatform.x,
          },
        );
        expect(
          store.postsOf(PublishPlatform.x).single.state,
          PostState.readyToShare,
        );
        expect(renderer.drawn.single.kind, CardKind.goal);
        expect(renderer.drawn.single.scorer, 'سالم الدوسري');
        expect(host.files.keys.single, startsWith('goals/$fixture/'));
        // Facebook's hold (3 minutes) has passed: sent in the same run.
        expect(facebook.sent.single, contains('سالم الدوسري'));
        // Instagram waits its own eight minutes.
        expect(instagram.sent, isEmpty);
      },
    );

    test('is queued once, however many runs see it', () async {
      board.show(fixture, 1, 0, at(12));
      for (var minute = 12; minute <= 30; minute++) {
        await tick()(now: at(minute));
      }

      expect(store.goals, hasLength(1));
      expect(store.posts, hasLength(3));
      expect(facebook.sent, hasLength(1));
      expect(instagram.sent, hasLength(1));
    });

    test('ruled out before its hold is never posted', () async {
      board.show(fixture, 1, 0, at(12));
      await tick()(now: at(12));
      board.show(fixture, 0, 0, at(14));

      await tick()(now: at(14));
      await tick()(now: at(20));

      expect(store.goals.single.state, StoredGoalState.withdrawn);
      expect(store.posts, isEmpty);
    });

    test(
      'ruled out after it was posted is corrected where it can be',
      () async {
        board.show(fixture, 1, 0, at(12));
        for (var minute = 12; minute <= 21; minute++) {
          await tick()(now: at(minute));
        }
        expect(instagram.sent, hasLength(1));
        board.show(fixture, 0, 0, at(22));

        final report = await tick()(now: at(22));

        final corrections = <FakePost>[
          for (final post in store.posts)
            if (post.post.kind == PostKind.correction) post,
        ];
        expect(
          corrections.map((p) => p.post.platform).toSet(),
          <PublishPlatform>{PublishPlatform.facebook},
        );
        expect(facebook.sent.last, contains('ألغى حكم الفيديو'));
        expect(corrections.single.state, PostState.published);
        // Words only: the goal's picture would say the opposite.
        expect(corrections.single.post.cardPath, isNull);
        expect(facebook.withPicture.last, isFalse);
        expect(
          (report as Ok<PublisherTickReport>).value.attention.single.code,
          'publisher.instagram_goal_withdrawn',
        );
      },
    );

    test('waits for the scorer a while, then goes out without him', () async {
      board.show(fixture, 0, 1, at(40), minute: 39);
      await tick(askDetails: true)(now: at(40));

      await tick(askDetails: true)(now: at(43));
      expect(store.goals.single.state, StoredGoalState.pending);
      await tick(askDetails: true)(now: at(45));
      expect(store.goals.single.state, StoredGoalState.pending);
      await tick(askDetails: true)(now: at(47));

      expect(details.asked, 3);
      expect(store.goals.single.state, StoredGoalState.confirmed);
      expect(store.goals.single.scorer, isNull);
      expect(store.goals.single.minuteLabel, '39');
      expect(
        store.postsOf(PublishPlatform.facebook).single.post.body,
        contains('النصر'),
      );
    });
  });

  group('a match', () {
    test('with no running score on the board is left alone', () async {
      await tick()(now: at(30));

      expect(store.goals, isEmpty);
      expect(store.coverage[fixture]!.knownAt, isNull);
    });

    test(
      'picked after kickoff takes the score as it stands, not as goals',
      () async {
        store.coverage[fixture]!.addedAt = at(50);
        board.show(fixture, 2, 1, at(51));

        await tick()(now: at(51));

        expect(store.goals, isEmpty);
        expect(store.coverage[fixture]!.known, const ScoreLine(2, 1));
      },
    );

    test('with a result gets its final posts once', () async {
      store.coverage[fixture]!.result = const ScoreLine(2, 1);

      await tick()(now: at(130));
      await tick()(now: at(131));

      final finals = <FakePost>[
        for (final post in store.posts)
          if (post.post.kind == PostKind.finalResult) post,
      ];
      expect(finals, hasLength(3));
      expect(renderer.drawn.single.kind, CardKind.finalResult);
      expect(renderer.drawn.single.verdict, 'فوز الهلال');
      expect(facebook.sent.single, contains('الهلال 2 - 1 النصر'));
    });

    test('draws the crests of the clubs that have one on file', () async {
      final crests = _Crests()
        ..files['الهلال'] = const <int>[0x89, 0x50, 0x4E, 0x47, 1];
      store.coverage[fixture]!.result = const ScoreLine(2, 1);

      await tick(crests: crests)(now: at(130));

      final spec = renderer.drawn.single;
      expect(spec.homeCrest, const <int>[0x89, 0x50, 0x4E, 0x47, 1]);
      expect(spec.awayCrest, isNull);
      expect(spec.homeBadge.label, isNotEmpty);
    });
  });

  group('sending', () {
    test('a dry run keeps every post for review and sends nothing', () async {
      board.show(fixture, 1, 0, at(12));
      for (var minute = 12; minute <= 21; minute++) {
        await tick(mode: PublisherMode.dryRun)(now: at(minute));
      }

      expect(facebook.sent, isEmpty);
      expect(instagram.sent, isEmpty);
      expect(
        store.postsOf(PublishPlatform.facebook).single.state,
        PostState.dryRun,
      );
      expect(
        store.postsOf(PublishPlatform.instagram).single.state,
        PostState.dryRun,
      );
    });

    test('one platform failing never holds another back', () async {
      instagram.next = const PosterRejected('graph_400: bad image');
      board.show(fixture, 1, 0, at(12));
      for (var minute = 12; minute <= 21; minute++) {
        await tick()(now: at(minute));
      }

      expect(
        store.postsOf(PublishPlatform.facebook).single.state,
        PostState.published,
      );
      expect(
        store.postsOf(PublishPlatform.instagram).single.state,
        PostState.failed,
      );
    });

    test('a rate limit puts the post back for later', () async {
      facebook.next = const PosterRetry(
        'rate_limited',
        after: Duration(minutes: 10),
      );
      board.show(fixture, 1, 0, at(12));
      await tick()(now: at(12));
      await tick()(now: at(15));

      final post = store.postsOf(PublishPlatform.facebook).single;
      expect(post.state, PostState.queued);
      expect(post.attempts, 1);
      expect(post.nextAttemptAt, at(25));
    });

    test(
      'a cut after sending is uncertain, told to an admin, not resent',
      () async {
        facebook.next = const PosterUncertain('graph_cut');
        board.show(fixture, 1, 0, at(12));
        await tick()(now: at(12));

        final report = await tick()(now: at(15));
        await tick()(now: at(16));

        expect(facebook.sent, hasLength(1));
        expect(
          store.postsOf(PublishPlatform.facebook).single.state,
          PostState.uncertain,
        );
        expect(
          (report as Ok<PublisherTickReport>).value.attention.single.code,
          'publisher.post_uncertain',
        );
      },
    );

    test(
      'a claim the server never finished is uncertain, not resent',
      () async {
        board.show(fixture, 1, 0, at(12));
        await tick()(now: at(12));
        await tick(mode: PublisherMode.dryRun)(now: at(15));
        final row = store.postsOf(PublishPlatform.facebook).single
          ..state = PostState.queued
          ..claimedUntil = at(15);

        await tick()(now: at(16));

        expect(row.state, PostState.uncertain);
        expect(facebook.sent, isEmpty);
      },
    );

    test('a full day skips the goal post', () async {
      store.enable(
        PublishPlatform.facebook,
        change: (s) => s.copyWith(dailyCap: 0),
      );
      board.show(fixture, 1, 0, at(12));
      await tick()(now: at(12));
      await tick()(now: at(15));

      final post = store.postsOf(PublishPlatform.facebook).single;
      expect(post.state, PostState.skipped);
      expect(post.error, 'daily_cap');
      expect(facebook.sent, isEmpty);
    });

    test('a platform turned off takes no goal', () async {
      store.stored[PublishPlatform.instagram] = PlatformIntensity.defaults(
        PublishPlatform.instagram,
      );
      board.show(fixture, 1, 0, at(12));
      await tick()(now: at(12));
      await tick()(now: at(15));

      expect(store.postsOf(PublishPlatform.instagram), isEmpty);
    });

    test('reads the reach of a post a day after it went out', () async {
      board.show(fixture, 1, 0, at(12));
      await tick()(now: at(12));
      await tick()(now: at(15));

      await tick()(now: at(15 + 24 * 60 + 1));

      final post = store.postsOf(PublishPlatform.facebook).single;
      expect(store.metrics[post.id]?.reactions, 7);
    });
  });

  test('PublisherMode reads NUKHBA_PUBLISHER', () {
    expect(PublisherMode.parse('on'), PublisherMode.on);
    expect(PublisherMode.parse(' DRY_RUN '), PublisherMode.dryRun);
    expect(PublisherMode.parse(null), PublisherMode.off);
    expect(PublisherMode.parse('yes'), PublisherMode.off);
  });
}
