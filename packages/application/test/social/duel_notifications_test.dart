import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import '../notification/fakes.dart' show InMemoryNotificationRepository;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'duel_application_fakes.dart';

const _user = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _target = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _season = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _fixture = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _participant = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
// The id FakeDuelChallengeRepository gives every created challenge.
const _challenge = '11111111-1111-1111-1111-111111111111';

// 12:00 UTC is 15:00 in Riyadh: outside the quiet hours.
final DateTime _day = DateTime.utc(2026, 10, 5, 12);
// 21:00 UTC is 00:00 in Riyadh: inside them.
final DateTime _night = DateTime.utc(2026, 10, 5, 21);

final class _Notices implements DuelNoticeReader {
  _Notices({this.challenged, this.accepted});

  final DuelNotice? challenged;
  final DuelNotice? accepted;
  int reads = 0;

  @override
  Future<Result<DuelNotice?>> challengedNotice(
    DuelChallengeId challengeId,
  ) async {
    reads++;
    return Result.ok(challenged);
  }

  @override
  Future<Result<DuelNotice?>> acceptedNotice(DuelId duelId) async {
    reads++;
    return Result.ok(accepted);
  }
}

final class _Sender implements PushSender {
  final List<String?> links = <String?>[];
  final List<String> titles = <String>[];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    links.add(link);
    titles.add(title);
    return const Result.ok(<String>[]);
  }
}

final class _Queue implements NotificationQueue {
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
  }) async => const Result.ok(<QueuedPush>[]);

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) async =>
      const Result.ok(null);
}

DuelNotice _notice({
  required String recipient,
  required String actor,
  List<String> tokens = const <String>['tok-1'],
}) => DuelNotice(
  recipientUserId: UserId(recipient),
  actorUserId: UserId(actor),
  actorName: 'Ali',
  code: 'ABCDEFGHJKMN',
  homeTeam: 'Home',
  awayTeam: 'Away',
  tokens: tokens,
  utcOffsetMinutes: 180,
);

DuelChallenge _privateChallenge() =>
    (DuelChallenge.create(
              id: const DuelChallengeId(_challenge),
              code: (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>).value,
              seasonId: const SeasonId(_season),
              fixture: const FixtureRef(_fixture),
              challengerParticipantId: const ParticipantId(_participant),
              targetUserId: const UserId(_target),
              capacity: 1,
              createdAt: _day,
            )
            as Ok<DuelChallenge>)
        .value;

NotifyDuelEvents _notifier({
  required _Notices notices,
  required InMemoryNotificationRepository notifications,
  required _Sender sender,
  required _Queue queue,
  DateTime? now,
}) {
  final clock = FixedClock(now ?? _day);
  return NotifyDuelEvents(
    notices: notices,
    create: CreateNotification(
      notifications: notifications,
      idGenerator: FakeIdGenerator(const [
        'f1f1f1f1-f1f1-4f1f-8f1f-f1f1f1f1f1f1',
        'f2f2f2f2-f2f2-4f2f-8f2f-f2f2f2f2f2f2',
        'f3f3f3f3-f3f3-4f3f-8f3f-f3f3f3f3f3f3',
      ]),
      clock: clock,
    ),
    sender: sender,
    queue: queue,
    idGenerator: FakeIdGenerator(const [
      'a9a9a9a9-a9a9-4a9a-8a9a-a9a9a9a9a9a9',
    ]),
    clock: clock,
  );
}

void main() {
  group('NotifyDuelEvents.challenged', () {
    test('tells the target once and links the push to the code', () async {
      final notifications = InMemoryNotificationRepository();
      final sender = _Sender();
      final notify = _notifier(
        notices: _Notices(
          challenged: _notice(recipient: _target, actor: _user),
        ),
        notifications: notifications,
        sender: sender,
        queue: _Queue(),
      );

      final first = await notify.challenged(_privateChallenge());
      final again = await notify.challenged(_privateChallenge());

      expect((first as Ok<bool>).value, isTrue);
      expect((again as Ok<bool>).value, isFalse);
      expect(notifications.countFor(_target), 1);
      expect(sender.links, <String?>['duel:ABCDEFGHJKMN']);
      expect(sender.titles.single, NotifyDuelEvents.challengedTitle);
    });

    test('an open challenge tells nobody', () async {
      final notices = _Notices(
        challenged: _notice(recipient: _target, actor: _user),
      );
      final open =
          (DuelChallenge.create(
                    id: const DuelChallengeId(_challenge),
                    code: (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>)
                        .value,
                    seasonId: const SeasonId(_season),
                    fixture: const FixtureRef(_fixture),
                    challengerParticipantId: const ParticipantId(_participant),
                    targetUserId: null,
                    createdAt: _day,
                  )
                  as Ok<DuelChallenge>)
              .value;

      final result = await _notifier(
        notices: notices,
        notifications: InMemoryNotificationRepository(),
        sender: _Sender(),
        queue: _Queue(),
      ).challenged(open);

      expect((result as Ok<bool>).value, isFalse);
      expect(notices.reads, 0);
    });

    test('in the quiet hours the push waits; the inbox row does not', () async {
      final notifications = InMemoryNotificationRepository();
      final sender = _Sender();
      final queue = _Queue();

      await _notifier(
        notices: _Notices(
          challenged: _notice(recipient: _target, actor: _user),
        ),
        notifications: notifications,
        sender: sender,
        queue: queue,
        now: _night,
      ).challenged(_privateChallenge());

      expect(notifications.countFor(_target), 1);
      expect(sender.links, isEmpty);
      expect(queue.queued.single.userId, const UserId(_target));
    });

    test('a player with no device still gets the inbox row', () async {
      final notifications = InMemoryNotificationRepository();
      final sender = _Sender();

      final result = await _notifier(
        notices: _Notices(
          challenged: _notice(
            recipient: _target,
            actor: _user,
            tokens: const <String>[],
          ),
        ),
        notifications: notifications,
        sender: sender,
        queue: _Queue(),
      ).challenged(_privateChallenge());

      expect((result as Ok<bool>).value, isTrue);
      expect(notifications.countFor(_target), 1);
      expect(sender.links, isEmpty);
    });
  });

  test('accepted tells the challenger with the duels link', () async {
    final notifications = InMemoryNotificationRepository();
    final sender = _Sender();
    final duel = Duel.fromStored(
      id: const DuelId('22222222-2222-4222-8222-222222222222'),
      challengeId: const DuelChallengeId(_challenge),
      fixture: const FixtureRef(_fixture),
      challengerParticipantId: const ParticipantId(_participant),
      opponentParticipantId: const ParticipantId(
        '99999999-9999-4999-8999-999999999999',
      ),
      acceptedAt: _day,
      createdAt: _day,
    );

    final result = await _notifier(
      notices: _Notices(
        accepted: _notice(recipient: _user, actor: _target),
      ),
      notifications: notifications,
      sender: sender,
      queue: _Queue(),
    ).accepted(duel);

    expect((result as Ok<bool>).value, isTrue);
    expect(notifications.countFor(_user), 1);
    expect(sender.links, <String?>[PushLink.duel]);
  });

  test('creating a private challenge tells its target', () async {
    final competition = FakeCompetitionRepository();
    final predictions = FakeFixturePredictionRepository();
    final schedules = FakeFixtureScheduleRepository();
    competition.seedParticipant(
      Participant.fromStored(
        id: const ParticipantId(_participant),
        seasonId: const SeasonId(_season),
        userId: const UserId(_user),
        status: ParticipantStatus.active,
        joinedAt: _day.subtract(const Duration(days: 1)),
      ),
    );
    predictions.seedSeasonFixture(
      SeasonFixture.fromStored(
        seasonId: const SeasonId(_season),
        fixture: const FixtureRef(_fixture),
        displayOrder: 1,
      ),
    );
    predictions.seedPrediction(
      FixturePrediction.fromStored(
        id: const PredictionId('77777777-7777-4777-8777-777777777777'),
        fixture: const FixtureRef(_fixture),
        participantId: const ParticipantId(_participant),
        homeGoals: 1,
        awayGoals: 0,
        isDouble: false,
      ),
      _day,
    );
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(_fixture),
        homeTeam: 'Home',
        awayTeam: 'Away',
        kickoffAt: _day.add(const Duration(hours: 2)),
      ),
    );
    final notifications = InMemoryNotificationRepository();
    final sender = _Sender();

    final result =
        await CreateDuelChallenge(
          duels: FakeDuelChallengeRepository(),
          competition: competition,
          predictions: predictions,
          schedules: schedules,
          clock: FixedClock(_day),
          notify: _notifier(
            notices: _Notices(
              challenged: _notice(recipient: _target, actor: _user),
            ),
            notifications: notifications,
            sender: sender,
            queue: _Queue(),
          ),
        ).call(
          principal: userPrincipal(_user),
          seasonId: _season,
          fixtureId: _fixture,
          capacity: 1,
          targetUserId: _target,
        );

    expect(result, isA<Ok<DuelChallenge>>());
    expect(notifications.countFor(_target), 1);
    expect(sender.links, <String?>['duel:ABCDEFGHJKMN']);
  });

  group('SearchDuelPlayers', () {
    test('a short query searches nothing', () async {
      final directory = _Directory();
      final result = await SearchDuelPlayers(
        players: directory,
      ).call(principal: userPrincipal(_user), query: ' a ');
      expect((result as Ok<List<DuelPlayer>>).value, isEmpty);
      expect(directory.queries, isEmpty);
    });

    test('searches the trimmed name, never the caller', () async {
      final directory = _Directory();
      final result = await SearchDuelPlayers(
        players: directory,
      ).call(principal: userPrincipal(_user), query: '  Bad ');
      expect((result as Ok<List<DuelPlayer>>).value.single.displayName, 'Badr');
      expect(directory.queries.single, 'Bad');
      expect(directory.excluded.single, const UserId(_user));
    });
  });
}

final class _Directory implements DuelPlayerDirectory {
  final List<String> queries = <String>[];
  final List<UserId> excluded = <UserId>[];

  @override
  Future<Result<List<DuelPlayer>>> search({
    required String query,
    required UserId excluding,
    required int limit,
  }) async {
    queries.add(query);
    excluded.add(excluding);
    return const Result.ok(<DuelPlayer>[
      DuelPlayer(userId: UserId(_target), displayName: 'Badr'),
    ]);
  }
}
