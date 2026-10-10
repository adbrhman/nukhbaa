/// The predictions board's wire shape (2026-10-11) survives a real JSON
/// round trip, carries a refused column without data, and reads an empty
/// or partial payload without failing.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

void main() {
  test('a shown column and a refused one survive the wire', () {
    const board = PredictionsBoardDto(
      seasonId: 's-1',
      columns: [
        PredictionsBoardColumnDto(
          fixtureId: 'f-1',
          predictions: [
            FixturePredictionDto(
              id: 'p-1',
              participantId: 'u-1',
              fixtureId: 'f-1',
              submittedAt: '2026-10-10T12:00:00.000Z',
              homeGoals: 2,
              awayGoals: 1,
              isDouble: true,
              displayName: 'سامي',
            ),
          ],
          scores: FixtureScoresDto(
            fixtureId: 'f-1',
            resultHomeGoals: 2,
            resultAwayGoals: 1,
            scores: [
              ParticipantFixtureScoreDto(
                fixtureId: 'f-1',
                participantId: 'u-1',
                rulesetVersion: 1,
                grade: 'exact_scoreline',
                points: 6,
              ),
            ],
          ),
          reactions: PredictionReactionsDto(
            reactions: [
              PredictionReactionTallyDto(
                participantId: 'u-1',
                counts: {'fire': 2},
                mine: 'fire',
              ),
            ],
          ),
        ),
        PredictionsBoardColumnDto(
          fixtureId: 'f-2',
          errorCode: 'prediction.fixture_not_started',
        ),
      ],
    );

    final back = PredictionsBoardDto.fromJson(_wire(board.toJson()));

    expect(back.toJson(), board.toJson());
    final shown = back.of('f-1')!;
    expect(shown.predictions.single.displayName, 'سامي');
    expect(shown.scores!.scores.single.points, 6);
    expect(shown.reactions!.of('u-1')!.mine, 'fire');
    final refused = back.of('f-2')!;
    expect(refused.errorCode, 'prediction.fixture_not_started');
    expect(refused.retryable, isFalse);
    expect(refused.predictions, isEmpty);
    expect(refused.scores, isNull);
    expect(back.of('f-3'), isNull);
  });

  test('an empty payload reads as an empty board', () {
    final board = PredictionsBoardDto.fromJson(const <String, Object?>{});

    expect(board.schemaVersion, 1);
    expect(board.seasonId, '');
    expect(board.columns, isEmpty);
  });

  test('a passing failure is marked retryable', () {
    final column = PredictionsBoardColumnDto.fromJson(const {
      'fixture_id': 'f-9',
      'error_code': 'db.query_timeout',
      'retryable': true,
    });

    expect(column.retryable, isTrue);
    expect(column.reactions, isNull);
  });
}
