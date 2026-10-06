import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/duel-wins/index.dart' as route;
import 'competition_route_harness.dart';

const _winner = '99999999-9999-9999-9999-999999999999';

final class _Records implements DuelRecordReader {
  @override
  Future<Result<Map<ParticipantId, int>>> winsInSeason(
    SeasonId seasonId,
  ) async => Result.ok({
    (ParticipantId.tryParse(_winner) as Ok<ParticipantId>).value: 2,
  });
}

/// `GET /seasons/{id}/duel-wins` through the real wiring: a member reads
/// every player's wins; anyone else is refused like the leaderboard.
void main() {
  CompositionRoot root({required bool member}) {
    final competition = InMemoryCompetitionRepository();
    if (member) {
      competition.participants.add(
        Participant.fromStored(
          id: (ParticipantId.tryParse(_winner) as Ok<ParticipantId>).value,
          seasonId: (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
          userId: const UserId(kUserId),
          status: ParticipantStatus.active,
          joinedAt: DateTime.utc(2026, 10),
        ),
      );
    }
    return CompositionRoot.forTesting(
      listSeasonDuelWins: ListSeasonDuelWins(
        competition: competition,
        records: _Records(),
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
        kSeasonId,
      );

  test('a member reads the wins of the season', () async {
    final response = await get(root(member: true));

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect(body['wins'], {_winner: 2});
  });

  test('someone outside the season is refused (401)', () async {
    final response = await get(root(member: false));

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(
      (await decodeBody(response))['code'],
      'leaderboard.not_a_participant',
    );
  });

  test('any other method is 405', () async {
    final response = await get(root(member: true), method: HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
