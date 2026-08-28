import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _otherUser = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
const _competitionA = '11111111-1111-1111-1111-111111111111';
const _competitionB = '22222222-2222-2222-2222-222222222222';
const _seasonA = '33333333-3333-3333-3333-333333333333';
const _seasonB = '44444444-4444-4444-4444-444444444444';
const _seasonFuture = '55555555-5555-5555-5555-555555555555';
const _participantA = '66666666-6666-6666-6666-666666666666';
const _participantB = '77777777-7777-7777-7777-777777777777';
const _participantWithdrawn = '88888888-8888-8888-8888-888888888888';
const _participantFuture = '99999999-9999-9999-9999-999999999999';
const _foreignParticipant = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

final _now = DateTime.utc(2026, 8, 15);

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
  required DateTime startAt,
  required DateTime endAt,
  String label = 'x',
}) => CompetitionSeason.fromStored(
  id: SeasonId(id),
  competitionId: CompetitionId(competitionId),
  label: label,
  startAt: startAt,
  endAt: endAt,
);

Participant _participant({
  required String id,
  required String seasonId,
  required String userId,
  ParticipantStatus status = ParticipantStatus.active,
}) => Participant.fromStored(
  id: ParticipantId(id),
  seasonId: SeasonId(seasonId),
  userId: UserId(userId),
  status: status,
  joinedAt: _now,
);

void main() {
  late FakeCompetitionRepository repo;
  late ListMyActiveSeasons useCase;

  setUp(() {
    repo = FakeCompetitionRepository();
    useCase = ListMyActiveSeasons(
      competitionRepository: repo,
      clock: FixedClock(_now),
    );
  });

  test(
    'lists every season the caller is an active participant in, whose '
    'window covers "now"',
    () async {
      repo
        ..seedCompetition(_competition(id: _competitionA, name: 'Alpha'))
        ..seedSeason(
          _season(
            id: _seasonA,
            competitionId: _competitionA,
            startAt: DateTime.utc(2026, 8),
            endAt: DateTime.utc(2026, 9),
          ),
        )
        ..seedParticipant(
          _participant(id: _participantA, seasonId: _seasonA, userId: _user),
        );

      final result = await useCase(principal: userPrincipal(_user));

      final list = (result as Ok<List<ParticipantSeasonFeedEntry>>).value;
      expect(list, hasLength(1));
      expect(list.single.seasonId, const SeasonId(_seasonA));
      expect(list.single.competitionId, const CompetitionId(_competitionA));
      expect(list.single.competitionName, 'Alpha');
    },
  );

  test("excludes another user's participation even when present", () async {
    repo
      ..seedCompetition(_competition(id: _competitionA, name: 'Alpha'))
      ..seedSeason(
        _season(
          id: _seasonA,
          competitionId: _competitionA,
          startAt: DateTime.utc(2026, 8),
          endAt: DateTime.utc(2026, 9),
        ),
      )
      ..seedParticipant(
        _participant(
          id: _foreignParticipant,
          seasonId: _seasonA,
          userId: _otherUser,
        ),
      );

    final result = await useCase(principal: userPrincipal(_user));

    expect((result as Ok<List<ParticipantSeasonFeedEntry>>).value, isEmpty);
  });

  test('excludes a withdrawn participation', () async {
    repo
      ..seedCompetition(_competition(id: _competitionA, name: 'Alpha'))
      ..seedSeason(
        _season(
          id: _seasonA,
          competitionId: _competitionA,
          startAt: DateTime.utc(2026, 8),
          endAt: DateTime.utc(2026, 9),
        ),
      )
      ..seedParticipant(
        _participant(
          id: _participantWithdrawn,
          seasonId: _seasonA,
          userId: _user,
          status: ParticipantStatus.withdrawn,
        ),
      );

    final result = await useCase(principal: userPrincipal(_user));

    expect((result as Ok<List<ParticipantSeasonFeedEntry>>).value, isEmpty);
  });

  test(
    'excludes a season whose window does not cover "now" (future season)',
    () async {
      repo
        ..seedCompetition(_competition(id: _competitionA, name: 'Alpha'))
        ..seedSeason(
          _season(
            id: _seasonFuture,
            competitionId: _competitionA,
            startAt: DateTime.utc(2026, 9),
            endAt: DateTime.utc(2026, 10),
          ),
        )
        ..seedParticipant(
          _participant(
            id: _participantFuture,
            seasonId: _seasonFuture,
            userId: _user,
          ),
        );

      final result = await useCase(principal: userPrincipal(_user));

      expect((result as Ok<List<ParticipantSeasonFeedEntry>>).value, isEmpty);
    },
  );

  test(
    'orders by competition name, then season label, matching the '
    'repository contract',
    () async {
      repo
        ..seedCompetition(_competition(id: _competitionB, name: 'Zeta'))
        ..seedCompetition(_competition(id: _competitionA, name: 'Alpha'))
        ..seedSeason(
          _season(
            id: _seasonB,
            competitionId: _competitionB,
            startAt: DateTime.utc(2026, 8),
            endAt: DateTime.utc(2026, 9),
            label: 'August',
          ),
        )
        ..seedSeason(
          _season(
            id: _seasonA,
            competitionId: _competitionA,
            startAt: DateTime.utc(2026, 8),
            endAt: DateTime.utc(2026, 9),
            label: 'August',
          ),
        )
        ..seedParticipant(
          _participant(id: _participantB, seasonId: _seasonB, userId: _user),
        )
        ..seedParticipant(
          _participant(id: _participantA, seasonId: _seasonA, userId: _user),
        );

      final result = await useCase(principal: userPrincipal(_user));

      final list = (result as Ok<List<ParticipantSeasonFeedEntry>>).value;
      expect(list, hasLength(2));
      expect(list.first.competitionName, 'Alpha');
      expect(list.last.competitionName, 'Zeta');
    },
  );

  test('a caller in no active season right now gets an empty list', () async {
    final result = await useCase(principal: userPrincipal(_user));

    expect((result as Ok<List<ParticipantSeasonFeedEntry>>).value, isEmpty);
  });

  test('propagates a repository failure unchanged', () async {
    repo.failNextWith(
      const AppError.transient('competition.transient_failure', 'db down'),
    );

    final result = await useCase(principal: userPrincipal(_user));

    final error = (result as Err<List<ParticipantSeasonFeedEntry>>).error;
    expect(error.kind, ErrorKind.transient);
    expect(error.code, 'competition.transient_failure');
  });
}
