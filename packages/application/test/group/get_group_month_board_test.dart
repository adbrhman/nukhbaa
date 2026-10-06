import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart' show userPrincipal;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../scoring/fakes.dart' show scoringParticipant;
import 'fakes.dart' show InMemoryGroupRepository;

const _group = '11111111-1111-1111-1111-111111111111';
const _season = '22222222-2222-2222-2222-222222222222';
const _fixture = '33333333-3333-3333-3333-333333333333';
const _me = '41111111-1111-1111-1111-111111111111';
const _friend = '42222222-1111-1111-1111-111111111111';
const _stranger = '43333333-1111-1111-1111-111111111111';
const _idle = '44444444-1111-1111-1111-111111111111';
const _pMe = '51111111-1111-1111-1111-111111111111';
const _pFriend = '52222222-1111-1111-1111-111111111111';
const _pStranger = '53333333-1111-1111-1111-111111111111';

final class _Totals implements FixtureTotalsReader {
  final List<ParticipantFixtureTotals> lines = [
    for (final (String id, int points, int exact) in [
      (_pStranger, 30, 10),
      (_pFriend, 9, 3),
      (_pMe, 6, 2),
    ])
      (ParticipantFixtureTotals.of(
                participantId: ParticipantId(id),
                totalPoints: points,
                fixturesScored: 12,
                exactCount: exact,
                decidedCount: 12,
              )
              as Ok<ParticipantFixtureTotals>)
          .value,
  ];

  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async => Result.ok(lines);
}

final class _Participants implements ParticipantReader {
  @override
  Future<Result<Participant?>> findParticipantById(ParticipantId id) async =>
      const Result.ok(null);

  @override
  Future<Result<Map<String, String>>> findDisplayNames(
    List<ParticipantId> ids,
  ) async => Result.ok({
    for (final ParticipantId id in ids)
      id.value: id.value == _pMe ? 'Me' : 'Friend',
  });

  @override
  Future<Result<Map<String, ParticipantAvatarRef>>> findAvatarRefs(
    List<ParticipantId> ids,
  ) async => const Result.ok({});
}

GroupMembership _member(String id, String user) => GroupMembership.fromStored(
  id: GroupMembershipId(id),
  groupId: const GroupId(_group),
  userId: UserId(user),
  role: GroupRole.member,
  joinedAt: DateTime.utc(2026, 10),
);

GetGroupMonthBoard _useCase() {
  final groups = InMemoryGroupRepository()
    ..seedMembership(_member('61111111-1111-1111-1111-111111111111', _me))
    ..seedMembership(_member('62222222-1111-1111-1111-111111111111', _friend))
    ..seedMembership(_member('63333333-1111-1111-1111-111111111111', _idle));
  final competition = FakeCompetitionRepository()
    ..seedParticipant(
      scoringParticipant(id: _pMe, seasonId: _season, userId: _me),
    )
    ..seedParticipant(
      scoringParticipant(id: _pFriend, seasonId: _season, userId: _friend),
    )
    ..seedParticipant(
      scoringParticipant(id: _pStranger, seasonId: _season, userId: _stranger),
    );
  final predictions = FakeFixturePredictionRepository()
    ..seedSeasonFixture(
      const SeasonFixture.fromStored(
        seasonId: SeasonId(_season),
        fixture: FixtureRef(_fixture),
        displayOrder: 1,
      ),
    );
  return GetGroupMonthBoard(
    groups: groups,
    competition: competition,
    fixturePredictions: predictions,
    totals: _Totals(),
    participants: _Participants(),
  );
}

void main() {
  test('the month board of the members only, ranked among them', () async {
    final result = await _useCase()(
      principal: userPrincipal(_me),
      groupId: _group,
      seasonId: _season,
    );

    final FixtureLeaderboard board = (result as Ok<FixtureLeaderboard>).value;
    expect(
      [
        for (final FixtureLeaderboardEntry e in board.entries)
          (e.rank, e.participantId.value, e.totalPoints),
      ],
      [(1, _pFriend, 9), (2, _pMe, 6)],
    );
  });

  test('someone outside the group is refused', () async {
    final result = await _useCase()(
      principal: userPrincipal(_stranger),
      groupId: _group,
      seasonId: _season,
    );

    expect(
      (result as Err<FixtureLeaderboard>).error.code,
      'group.not_a_member',
    );
  });

  test('a malformed group id is refused before any read', () async {
    final result = await _useCase()(
      principal: userPrincipal(_me),
      groupId: 'not-a-uuid',
      seasonId: _season,
    );

    expect(result, isA<Err<FixtureLeaderboard>>());
  });
}
