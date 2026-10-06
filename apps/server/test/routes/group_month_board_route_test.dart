import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/groups/[id]/seasons/[seasonId]/month-board/index.dart'
    as route;
import 'competition_route_harness.dart';

const _stranger = '99999999-9999-9999-9999-999999999999';
const _pStranger = '98989898-9898-9898-9898-989898989898';

final class _Predictions extends Mock implements FixturePredictionRepository {}

final class _Totals implements FixtureTotalsReader {
  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async => Result.ok([
    for (final (String id, int points) in [
      (_pStranger, 30),
      (kParticipantId, 6),
    ])
      (ParticipantFixtureTotals.of(
                participantId: ParticipantId(id),
                totalPoints: points,
                fixturesScored: 4,
                exactCount: 1,
                decidedCount: 4,
              )
              as Ok<ParticipantFixtureTotals>)
          .value,
  ]);
}

Participant _participant(String id, String user) => Participant.fromStored(
  id: ParticipantId(id),
  seasonId: const SeasonId(kSeasonId),
  userId: UserId(user),
  status: ParticipantStatus.active,
  joinedAt: DateTime.utc(2026, 10),
);

/// `GET /groups/{id}/seasons/{seasonId}/month-board` through the real
/// wiring: a member reads the month board of the group's members only; a
/// non-member is refused.
void main() {
  CompositionRoot root({required bool member}) {
    final groups = InMemoryGroupRepository();
    if (member) {
      groups.seedMembership(
        GroupMembership.fromStored(
          id: const GroupMembershipId(kMemberMembershipId),
          groupId: const GroupId(kGroupId),
          userId: const UserId(kUserId),
          role: GroupRole.member,
          joinedAt: DateTime.utc(2026, 10),
        ),
      );
    }
    final competition = InMemoryCompetitionRepository();
    competition.participants
      ..add(_participant(kParticipantId, kUserId))
      ..add(_participant(_pStranger, _stranger));
    final participants = InMemoryParticipantReader()
      ..add(_participant(kParticipantId, kUserId))
      ..add(_participant(_pStranger, _stranger));
    final predictions = _Predictions();
    when(
      () => predictions.listSeasonFixtures(const SeasonId(kSeasonId)),
    ).thenAnswer((_) async => const Result.ok([FixtureRef(kFixtureId)]));
    return CompositionRoot.forTesting(
      getGroupMonthBoard: GetGroupMonthBoard(
        groups: groups,
        competition: competition,
        fixturePredictions: predictions,
        totals: _Totals(),
        participants: participants,
      ),
    );
  }

  Future<Response> get(CompositionRoot r, {HttpMethod? method}) =>
      route.onRequest(
        wireContext(
          root: r,
          principal: userPrincipal(),
          method: method ?? HttpMethod.get,
        ),
        kGroupId,
        kSeasonId,
      );

  test('a member reads the board of the members only', () async {
    final response = await get(root(member: true));

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    final entries = body['entries']! as List<Object?>;
    expect(entries, hasLength(1));
    final entry = entries.single! as Map<String, Object?>;
    expect(entry['participant_id'], kParticipantId);
    expect(entry['rank'], 1);
    expect(entry['total_points'], 6);
  });

  test('someone outside the group is refused (401)', () async {
    final response = await get(root(member: false));

    expect(response.statusCode, HttpStatus.unauthorized);
    expect((await decodeBody(response))['code'], 'group.not_a_member');
  });

  test('any other method is 405', () async {
    final response = await get(root(member: true), method: HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
