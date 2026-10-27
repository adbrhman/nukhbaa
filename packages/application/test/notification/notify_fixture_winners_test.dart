import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart' show FakeRulesetProvider, adminPrincipal;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import '../scoring/fake_fixture_score_repository.dart';
import '../scoring/fakes.dart' show FakeFixtureResultRepository;
import 'fakes.dart';

final class _FakeAnnouncements implements ScoreAnnouncementRepository {
  _FakeAnnouncements({this.utcOffsetMinutes, this.targets});

  /// The clock the fake target reports; null: it never reported one.
  final int? utcOffsetMinutes;

  /// The targets to answer with; null: the one target below.
  final List<ScoreNoticeTarget>? targets;

  List<ParticipantId> asked = const <ParticipantId>[];

  /// The keep list of every withdrawal, in order.
  final List<List<ParticipantId>> withdrawals = <List<ParticipantId>>[];

  @override
  Future<Result<int>> withdrawExactNotices({
    required FixtureRef fixture,
    required List<ParticipantId> keep,
  }) async {
    withdrawals.add(keep);
    return const Result.ok(0);
  }

  @override
  Future<Result<List<ScoreNoticeTarget>>> targetsForParticipants(
    List<ParticipantId> participantIds,
  ) async {
    asked = participantIds;
    final given = targets;
    if (given != null) {
      return Result.ok(given);
    }
    return Result.ok(<ScoreNoticeTarget>[
      ScoreNoticeTarget(
        participantId:
            (ParticipantId.tryParse(uuidB) as Ok<ParticipantId>).value,
        userId: (UserId.tryParse(uuidD) as Ok<UserId>).value,
        tokens: const <String>['token-1'],
        utcOffsetMinutes: utcOffsetMinutes,
      ),
    ]);
  }

  @override
  Future<Result<String?>> matchLabel(FixtureRef fixture) async =>
      const Result.ok('Home x Away');
}

final class _FakeSender implements PushSender {
  final List<String> titles = <String>[];
  final List<String> bodies = <String>[];
  final List<List<String>> tokens = <List<String>>[];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    titles.add(title);
    bodies.add(body);
    this.tokens.add(tokens);
    return const Result.ok(<String>[]);
  }
}

/// A [NotificationQueue] that records what it was asked to hold.
final class _FakeQueue implements NotificationQueue {
  final List<PushToQueue> queued = <PushToQueue>[];

  @override
  Future<Result<void>> enqueue(List<PushToQueue> pushes) async {
    queued.addAll(pushes);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<QueuedPush>>> claimDue({
    required DateTime now,
    required int limit,
  }) => throw StateError('the notifier never claims');

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) =>
      throw StateError('the notifier never forgets tokens');
}

ParticipantFixtureScore _score({
  required String participantId,
  required FixtureScoreGrade grade,
  required int points,
}) =>
    (ParticipantFixtureScore.fromGraded(
              fixture: (FixtureRef.tryParse(uuidA) as Ok<FixtureRef>).value,
              participantId:
                  (ParticipantId.tryParse(participantId) as Ok<ParticipantId>)
                      .value,
              rulesetVersion: 1,
              result: FixtureScoreResult(
                fixture: (FixtureRef.tryParse(uuidA) as Ok<FixtureRef>).value,
                grade: grade,
                points: points,
              ),
            )
            as Ok<ParticipantFixtureScore>)
        .value;

void main() {
  late _FakeAnnouncements announcements;
  late _FakeSender sender;
  late InMemoryNotificationRepository notifications;
  late _FakeQueue queue;
  late NotifyFixtureWinners useCase;

  setUp(() {
    announcements = _FakeAnnouncements();
    sender = _FakeSender();
    notifications = InMemoryNotificationRepository();
    queue = _FakeQueue();
    useCase = NotifyFixtureWinners(
      announcements: announcements,
      sender: sender,
      create: CreateNotification(
        notifications: notifications,
        idGenerator: FakeIdGenerator(<String>[
          '55555555-5555-4555-8555-000000000001',
          '55555555-5555-4555-8555-000000000002',
        ]),
        clock: FakeClock(DateTime.utc(2026, 9, 12, 18)),
      ),
      queue: queue,
      idGenerator: FakeIdGenerator(<String>[uuidA]),
      clock: FakeClock(DateTime.utc(2026, 9, 12, 18)),
    );
  });

  // Builds the use-case at [now], for a target whose clock is [offset].
  NotifyFixtureWinners useCaseAt(DateTime now, {int? offset}) {
    return NotifyFixtureWinners(
      announcements: _FakeAnnouncements(utcOffsetMinutes: offset),
      sender: sender,
      create: CreateNotification(
        notifications: notifications,
        idGenerator: FakeIdGenerator(<String>[
          '55555555-5555-4555-8555-000000000003',
        ]),
        clock: FakeClock(now),
      ),
      queue: queue,
      idGenerator: FakeIdGenerator(<String>[uuidA]),
      clock: FakeClock(now),
    );
  }

  FixtureRef fixture() => (FixtureRef.tryParse(uuidA) as Ok<FixtureRef>).value;

  test('only exact callers are asked about and pushed to', () async {
    final r = await useCase(
      fixture: fixture(),
      scores: <ParticipantFixtureScore>[
        _score(
          participantId: uuidB,
          grade: FixtureScoreGrade.exactScoreline,
          points: 3,
        ),
        _score(
          participantId: uuidC,
          grade: FixtureScoreGrade.correctOutcome,
          points: 0,
        ),
      ],
    );

    expect(r, isA<Ok<int>>());
    expect((r as Ok<int>).value, 1);
    expect(announcements.asked.length, 1);
    expect(announcements.asked.first.value, uuidB);
    expect(sender.titles.single, NotifyFixtureWinners.exactTitle);
    expect(sender.bodies.single, contains('+3'));
    expect(queue.queued, isEmpty);
  });

  test('a doubled hit gets its own title and its 6 points', () async {
    await useCase(
      fixture: fixture(),
      scores: <ParticipantFixtureScore>[
        _score(
          participantId: uuidB,
          grade: FixtureScoreGrade.exactScoreline,
          points: 6,
        ),
      ],
    );

    expect(sender.titles.single, NotifyFixtureWinners.doubleTitle);
    expect(sender.bodies.single, contains('+6'));
  });

  group('the sole exact call (script 159)', () {
    ParticipantId b() =>
        (ParticipantId.tryParse(uuidB) as Ok<ParticipantId>).value;

    test('6 points alone is an exact hit, not a double', () async {
      await useCase(
        fixture: fixture(),
        scores: <ParticipantFixtureScore>[
          _score(
            participantId: uuidB,
            grade: FixtureScoreGrade.exactScoreline,
            points: 6,
          ),
        ],
        doubled: <ParticipantId>{},
        solo: b(),
      );

      expect(sender.titles.single, NotifyFixtureWinners.exactTitle);
      expect(
        sender.bodies.single,
        'أصبت النتيجة '
        'بالضبط وحدك '
        'في Home x Away — +6 نقاط ✅',
      );
    });

    test('9 points alone on the double', () async {
      await useCase(
        fixture: fixture(),
        scores: <ParticipantFixtureScore>[
          _score(
            participantId: uuidB,
            grade: FixtureScoreGrade.exactScoreline,
            points: 9,
          ),
        ],
        doubled: <ParticipantId>{b()},
        solo: b(),
      );

      expect(sender.titles.single, NotifyFixtureWinners.doubleTitle);
      expect(sender.bodies.single, contains('وحدك'));
      expect(sender.bodies.single, contains('+9'));
    });

    test('ScoreFixture names the double and the one alone', () async {
      final FixtureRef match = fixture();
      final predictions = FakeFixturePredictionRepository();
      for (final (String id, String participant, int home) in [
        ('aaaaaaaa-0000-4000-8000-000000000001', uuidB, 2),
        ('aaaaaaaa-0000-4000-8000-000000000002', uuidC, 0),
      ]) {
        predictions.seedPrediction(
          FixturePrediction.fromStored(
            id: PredictionId(id),
            fixture: match,
            participantId: ParticipantId(participant),
            homeGoals: home,
            awayGoals: 1,
            isDouble: participant == uuidB,
          ),
          DateTime.utc(2026, 11, 2, 10),
        );
      }
      final results = FakeFixtureResultRepository()
        ..seed(
          FixtureResult.fromStored(fixture: match, homeGoals: 2, awayGoals: 1),
        );
      final schedules = FakeFixtureScheduleRepository()
        ..seed(
          (FixtureSchedule.create(
                    fixture: match,
                    homeTeam: 'Home',
                    awayTeam: 'Away',
                    kickoffAt: DateTime.utc(2026, 11, 2, 18),
                  )
                  as Ok<FixtureSchedule>)
              .value,
        );
      final scored = await ScoreFixture(
        fixturePredictionRepository: predictions,
        resultRepository: results,
        scoreRepository: FakeFixtureScoreRepository(),
        rulesetProvider: FakeRulesetProvider(
          RulesetSnapshot.create(
            payload: const {
              'format': 'football_scoreline',
              'points': {
                'exact_scoreline': 3,
                'correct_outcome': 0,
                'incorrect': 0,
              },
              'double_multiplier': 2,
              'solo_exact_bonus': 3,
              'solo_exact_since': '2026-10-31T21:00:00.000Z',
            },
            rulesetVersion: 4,
          ),
        ),
        fixtureScheduleRepository: schedules,
        winnerNotifier: useCase,
      )(principal: adminPrincipal('admin-1'), fixtureId: match.value);

      expect(scored, isA<Ok<List<ParticipantFixtureScore>>>());
      expect(sender.titles.single, NotifyFixtureWinners.doubleTitle);
      expect(sender.bodies.single, contains('وحدك'));
      expect(sender.bodies.single, contains('+9'));
    });

    test('a double shared with others: the double title, no alone', () async {
      await useCase(
        fixture: fixture(),
        scores: <ParticipantFixtureScore>[
          _score(
            participantId: uuidB,
            grade: FixtureScoreGrade.exactScoreline,
            points: 6,
          ),
        ],
        doubled: <ParticipantId>{b()},
      );

      expect(sender.titles.single, NotifyFixtureWinners.doubleTitle);
      expect(sender.bodies.single, isNot(contains('وحدك')));
    });
  });

  test(
    're-scoring the same fixture never rings the same phone twice',
    () async {
      final scores = <ParticipantFixtureScore>[
        _score(
          participantId: uuidB,
          grade: FixtureScoreGrade.exactScoreline,
          points: 3,
        ),
      ];

      await useCase(fixture: fixture(), scores: scores);
      final second = await useCase(fixture: fixture(), scores: scores);

      expect((second as Ok<int>).value, 0);
      expect(sender.titles.length, 1);
      expect(notifications.countFor(uuidD), 1);
    },
  );

  test('winners reading the same message share one send (M-32)', () async {
    ScoreNoticeTarget target(String participant, String user, String token) =>
        ScoreNoticeTarget(
          participantId:
              (ParticipantId.tryParse(participant) as Ok<ParticipantId>).value,
          userId: (UserId.tryParse(user) as Ok<UserId>).value,
          tokens: <String>[token],
        );
    final many = NotifyFixtureWinners(
      announcements: _FakeAnnouncements(
        targets: <ScoreNoticeTarget>[
          target(uuidB, uuidD, 'token-b'),
          target(uuidC, uuidA, 'token-c'),
        ],
      ),
      sender: sender,
      create: CreateNotification(
        notifications: notifications,
        idGenerator: FakeIdGenerator(<String>[
          '55555555-5555-4555-8555-000000000004',
          '55555555-5555-4555-8555-000000000005',
        ]),
        clock: FakeClock(DateTime.utc(2026, 9, 12, 18)),
      ),
      queue: queue,
      idGenerator: FakeIdGenerator(<String>[uuidA]),
      clock: FakeClock(DateTime.utc(2026, 9, 12, 18)),
    );

    final r = await many(
      fixture: fixture(),
      scores: <ParticipantFixtureScore>[
        _score(
          participantId: uuidB,
          grade: FixtureScoreGrade.exactScoreline,
          points: 3,
        ),
        _score(
          participantId: uuidC,
          grade: FixtureScoreGrade.exactScoreline,
          points: 3,
        ),
      ],
    );

    expect((r as Ok<int>).value, 2);
    expect(sender.titles, hasLength(1), reason: 'one send for one message');
    expect(
      sender.tokens.single,
      unorderedEquals(<String>['token-b', 'token-c']),
    );
  });

  test('a correction withdraws the notice of whoever no longer called it '
      '(L-27)', () async {
    final r = await useCase(
      fixture: fixture(),
      scores: <ParticipantFixtureScore>[
        _score(
          participantId: uuidB,
          grade: FixtureScoreGrade.correctOutcome,
          points: 0,
        ),
      ],
    );

    expect((r as Ok<int>).value, 0);
    expect(announcements.withdrawals.single, isEmpty);
    expect(sender.titles, isEmpty);
  });

  test('the exact callers are kept when the notices are withdrawn', () async {
    await useCase(
      fixture: fixture(),
      scores: <ParticipantFixtureScore>[
        _score(
          participantId: uuidB,
          grade: FixtureScoreGrade.exactScoreline,
          points: 3,
        ),
      ],
    );

    expect(
      announcements.withdrawals.single.map((ParticipantId p) => p.value),
      <String>[uuidB],
    );
  });

  test('nothing to announce is not an error', () async {
    final r = await useCase(
      fixture: fixture(),
      scores: <ParticipantFixtureScore>[
        _score(
          participantId: uuidC,
          grade: FixtureScoreGrade.incorrect,
          points: 0,
        ),
      ],
    );

    expect((r as Ok<int>).value, 0);
    expect(sender.titles, isEmpty);
  });

  group('quiet hours', () {
    final exactHit = <ParticipantFixtureScore>[
      _score(
        participantId: uuidB,
        grade: FixtureScoreGrade.exactScoreline,
        points: 3,
      ),
    ];

    test('a winner in their quiet hours is queued until 08:00', () async {
      // 21:00 UTC is 00:00 in Riyadh, and the target never reported a clock.
      final r = await useCaseAt(DateTime.utc(2026, 9, 12, 21))(
        fixture: fixture(),
        scores: exactHit,
      );

      expect((r as Ok<int>).value, 1);
      expect(sender.titles, isEmpty);
      expect(notifications.countFor(uuidD), 1);
      final push = queue.queued.single;
      expect(push.id, uuidA);
      expect(push.userId.value, uuidD);
      expect(push.title, NotifyFixtureWinners.exactTitle);
      expect(push.body, contains('+3'));
      expect(push.deliverAfter, DateTime.utc(2026, 9, 13, 5));
    });

    test('the reported clock decides, not Riyadh', () async {
      // 18:00 UTC is 21:00 in Riyadh (awake) but 02:00 at UTC+8 (quiet).
      final r = await useCaseAt(DateTime.utc(2026, 9, 12, 18), offset: 480)(
        fixture: fixture(),
        scores: exactHit,
      );

      expect((r as Ok<int>).value, 1);
      expect(sender.titles, isEmpty);
      expect(queue.queued.single.deliverAfter, DateTime.utc(2026, 9, 13));
    });

    test('a winner who is awake is pushed at once, not queued', () async {
      final r = await useCaseAt(DateTime.utc(2026, 9, 12, 12))(
        fixture: fixture(),
        scores: exactHit,
      );

      expect((r as Ok<int>).value, 1);
      expect(sender.titles, hasLength(1));
      expect(queue.queued, isEmpty);
    });
  });
}
