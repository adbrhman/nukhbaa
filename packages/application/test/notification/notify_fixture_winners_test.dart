import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

final class _FakeAnnouncements implements ScoreAnnouncementRepository {
  List<ParticipantId> asked = const <ParticipantId>[];

  @override
  Future<Result<List<ScoreNoticeTarget>>> targetsForParticipants(
    List<ParticipantId> participantIds,
  ) async {
    asked = participantIds;
    return Result.ok(<ScoreNoticeTarget>[
      ScoreNoticeTarget(
        participantId:
            (ParticipantId.tryParse(uuidB) as Ok<ParticipantId>).value,
        userId: (UserId.tryParse(uuidD) as Ok<UserId>).value,
        tokens: const <String>['token-1'],
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

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
  }) async {
    titles.add(title);
    bodies.add(body);
    return const Result.ok(<String>[]);
  }
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
  late NotifyFixtureWinners useCase;

  setUp(() {
    announcements = _FakeAnnouncements();
    sender = _FakeSender();
    notifications = InMemoryNotificationRepository();
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
    );
  });

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
}
