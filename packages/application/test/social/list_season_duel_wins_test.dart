import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart' show userPrincipal;
import '../scoring/fakes.dart' show scoringParticipant;

const _season = '11111111-1111-1111-1111-111111111111';
const _memberUser = '22222222-2222-2222-2222-222222222222';
const _outsiderUser = '33333333-3333-3333-3333-333333333333';
const _member = '44444444-4444-4444-4444-444444444444';
const _winner = '55555555-5555-5555-5555-555555555555';

final class _Records implements DuelRecordReader {
  _Records(this._wins);

  final Map<ParticipantId, int> _wins;
  final List<SeasonId> asked = [];

  @override
  Future<Result<Map<ParticipantId, int>>> winsInSeason(
    SeasonId seasonId,
  ) async {
    asked.add(seasonId);
    return Result.ok(_wins);
  }
}

ParticipantId _id(String raw) =>
    (ParticipantId.tryParse(raw) as Ok<ParticipantId>).value;

({ListSeasonDuelWins useCase, _Records records}) _harness() {
  final competition = FakeCompetitionRepository()
    ..seedParticipant(
      scoringParticipant(id: _member, seasonId: _season, userId: _memberUser),
    );
  final records = _Records({_id(_winner): 3});
  return (
    useCase: ListSeasonDuelWins(competition: competition, records: records),
    records: records,
  );
}

void main() {
  test('a member of the season reads every player duel wins', () async {
    final h = _harness();

    final result = await h.useCase(
      principal: userPrincipal(_memberUser),
      seasonId: _season,
    );

    expect((result as Ok<Map<ParticipantId, int>>).value, {_id(_winner): 3});
    expect(h.records.asked.single.value, _season);
  });

  test('someone outside the season reads nothing', () async {
    final h = _harness();

    final result = await h.useCase(
      principal: userPrincipal(_outsiderUser),
      seasonId: _season,
    );

    expect(
      (result as Err<Map<ParticipantId, int>>).error.code,
      'leaderboard.not_a_participant',
    );
    expect(h.records.asked, isEmpty);
  });

  test('a malformed season id is refused before any read', () async {
    final h = _harness();

    final result = await h.useCase(
      principal: userPrincipal(_memberUser),
      seasonId: 'not-a-uuid',
    );

    expect(
      (result as Err<Map<ParticipantId, int>>).error.kind,
      ErrorKind.validation,
    );
    expect(h.records.asked, isEmpty);
  });
}
