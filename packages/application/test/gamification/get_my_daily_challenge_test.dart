import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _competitionA = '11111111-1111-1111-1111-111111111111';
const _competitionB = '22222222-2222-2222-2222-222222222222';
const _seasonA = '33333333-3333-3333-3333-333333333333';
const _seasonB = '44444444-4444-4444-4444-444444444444';
const _participantA = '66666666-6666-6666-6666-666666666666';
const _participantB = '77777777-7777-7777-7777-777777777777';

/// 2026-09-15 21:00 UTC is 2026-09-16 00:00 in Riyadh: the instant that
/// proves the use-case asks about the RIYADH day, not the UTC one.
final _nowLateEvening = DateTime.utc(2026, 9, 15, 21);
final _riyadhDay = DateTime.utc(2026, 9, 16);

const _principal = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);

Competition _competition({required String id, required String name}) =>
    Competition.fromStored(
      id: CompetitionId(id),
      name: name,
      format: FormatType.footballScoreline,
      visibility: CompetitionVisibility.public,
    );

CompetitionSeason _season({
  required String id,
  required String competitionId,
}) => CompetitionSeason.fromStored(
  id: SeasonId(id),
  competitionId: CompetitionId(competitionId),
  label: '09/2026',
  startAt: DateTime.utc(2026, 9),
  endAt: DateTime.utc(2026, 10),
);

Participant _participant({required String id, required String seasonId}) =>
    Participant.fromStored(
      id: ParticipantId(id),
      seasonId: SeasonId(seasonId),
      userId: const UserId(_user),
      status: ParticipantStatus.active,
      joinedAt: DateTime.utc(2026, 9),
    );

/// Scripted [DailyChallengeRepository]: answers per season and records every
/// question, so a test can assert WHICH day was asked about.
final class _FakeDailyChallenges implements DailyChallengeRepository {
  _FakeDailyChallenges(this._bySeason, {AppError? failWith})
    : _failure = failWith;

  final Map<String, DailyChallengeProgress> _bySeason;
  final AppError? _failure;

  final List<DateTime> daysAsked = <DateTime>[];
  final List<String> seasonsAsked = <String>[];
  final List<String> participantsAsked = <String>[];

  @override
  Future<Result<DailyChallengeProgress>> progressOn({
    required SeasonId seasonId,
    required ParticipantId participantId,
    required DateTime day,
  }) async {
    daysAsked.add(day);
    seasonsAsked.add(seasonId.value);
    participantsAsked.add(participantId.value);
    final failure = _failure;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(
      _bySeason[seasonId.value] ??
          const DailyChallengeProgress(total: 0, predicted: 0),
    );
  }
}

void main() {
  late FakeCompetitionRepository competitions;

  GetMyDailyChallenge useCase(_FakeDailyChallenges challenges) =>
      GetMyDailyChallenge(
        competitionRepository: competitions,
        dailyChallenges: challenges,
        clock: FixedClock(_nowLateEvening),
      );

  void seedSeasonA() {
    competitions
      ..seedCompetition(_competition(id: _competitionA, name: 'Alpha'))
      ..seedSeason(_season(id: _seasonA, competitionId: _competitionA))
      ..seedParticipant(_participant(id: _participantA, seasonId: _seasonA));
  }

  setUp(() {
    competitions = FakeCompetitionRepository();
  });

  test('reports the caller coverage of today and asks about the Riyadh '
      'day', () async {
    seedSeasonA();
    final challenges = _FakeDailyChallenges({
      _seasonA: const DailyChallengeProgress(total: 3, predicted: 2),
    });

    final result = await useCase(challenges)(principal: _principal);

    final challenge = (result as Ok<MyDailyChallenge>).value;
    expect(challenge.total, 3);
    expect(challenge.predicted, 2);
    expect(challenge.isComplete, isFalse);
    expect(challenge.day, _riyadhDay);
    // 21:00 UTC is already tomorrow in Riyadh: the UTC date would be the 15th.
    expect(challenges.daysAsked.single, _riyadhDay);
    expect(challenges.participantsAsked.single, _participantA);
  });

  test('a fully predicted day is complete', () async {
    seedSeasonA();
    final challenges = _FakeDailyChallenges({
      _seasonA: const DailyChallengeProgress(total: 2, predicted: 2),
    });

    final result = await useCase(challenges)(principal: _principal);

    expect((result as Ok<MyDailyChallenge>).value.isComplete, isTrue);
  });

  test('a day with no fixtures is not complete', () async {
    seedSeasonA();
    final challenges = _FakeDailyChallenges({
      _seasonA: const DailyChallengeProgress(total: 0, predicted: 0),
    });

    final result = await useCase(challenges)(principal: _principal);

    final challenge = (result as Ok<MyDailyChallenge>).value;
    expect(challenge.total, 0);
    expect(challenge.isComplete, isFalse);
  });

  test('sums every season the caller is an active participant in', () async {
    seedSeasonA();
    competitions
      ..seedCompetition(_competition(id: _competitionB, name: 'Beta'))
      ..seedSeason(_season(id: _seasonB, competitionId: _competitionB))
      ..seedParticipant(_participant(id: _participantB, seasonId: _seasonB));
    final challenges = _FakeDailyChallenges({
      _seasonA: const DailyChallengeProgress(total: 2, predicted: 2),
      _seasonB: const DailyChallengeProgress(total: 3, predicted: 1),
    });

    final result = await useCase(challenges)(principal: _principal);

    final challenge = (result as Ok<MyDailyChallenge>).value;
    expect(challenge.total, 5);
    expect(challenge.predicted, 3);
    // Complete in one season is not complete for the day.
    expect(challenge.isComplete, isFalse);
    expect(challenges.seasonsAsked, containsAll(<String>[_seasonA, _seasonB]));
  });

  test(
    'a caller with no active season gets an empty, incomplete day',
    () async {
      final challenges = _FakeDailyChallenges(const {});

      final result = await useCase(challenges)(principal: _principal);

      final challenge = (result as Ok<MyDailyChallenge>).value;
      expect(challenge.total, 0);
      expect(challenge.predicted, 0);
      expect(challenge.isComplete, isFalse);
      // No season means no question was asked at all.
      expect(challenges.daysAsked, isEmpty);
    },
  );

  test('passes a repository failure through', () async {
    seedSeasonA();
    final challenges = _FakeDailyChallenges(
      const {},
      failWith: const AppError.transient('db.query_failed', 'boom'),
    );

    final result = await useCase(challenges)(principal: _principal);

    expect((result as Err<MyDailyChallenge>).error.code, 'db.query_failed');
  });
}
