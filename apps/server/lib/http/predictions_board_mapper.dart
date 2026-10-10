/// Projects the predictions board of a day ([GetPredictionsBoard]) onto
/// its wire shape, reusing the three per-fixture projections so a column
/// carries exactly what `GET .../fixtures/{id}/predictions`, `.../scores`
/// and `.../reactions` send (2026-10-11).
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:server/http/fixture_prediction_dto_mapper.dart';
import 'package:server/http/fixture_score_dto_mapper.dart';
import 'package:shared/shared.dart';

/// The board of [columns] in [seasonId] as the route sends it.
Map<String, Object?> predictionsBoardToJson(
  String seasonId,
  List<PredictionsBoardColumn> columns,
) => {
  'schema_version': PredictionsBoardDto.currentSchemaVersion,
  'season_id': seasonId,
  'columns': [for (final column in columns) _columnToJson(column)],
};

Map<String, Object?> _columnToJson(PredictionsBoardColumn column) {
  final error = column.error;
  final reveal = column.reveal;
  if (error != null || reveal == null) {
    return {
      'fixture_id': column.fixtureId,
      'error_code': error?.code ?? 'board.column_missing',
      'retryable': error?.kind == ErrorKind.transient,
      'predictions': const <Object?>[],
      'scores': null,
      'reactions': null,
    };
  }
  final reactions = column.reactions;
  return {
    'fixture_id': column.fixtureId,
    'error_code': null,
    'retryable': false,
    'predictions': [
      for (final view in reveal.predictions)
        fixturePredictionViewToJson(
          view,
          displayName:
              reveal.displayNames[view.prediction.participantId.value] ?? '',
        ),
    ],
    'scores': fixtureScoresToJson(
      column.fixtureId,
      column.scores,
      result: column.result,
    ),
    'reactions': reactions == null
        ? null
        : PredictionReactionsDto(
            reactions: [
              for (final tally in reactions)
                PredictionReactionTallyDto(
                  participantId: tally.targetParticipantId.value,
                  counts: {
                    for (final e in tally.counts.entries)
                      e.key.wireValue: e.value,
                  },
                  mine: tally.mine?.wireValue,
                ),
            ],
          ).toJson(),
  };
}
