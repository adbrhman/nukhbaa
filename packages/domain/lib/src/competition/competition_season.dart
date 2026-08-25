import 'package:domain/src/competition/competition_id.dart';
import 'package:domain/src/competition/season_id.dart';
import 'package:shared/shared.dart';

/// A season of a [Competition] (Database ADR, Section 3: Competition ->
/// CompetitionSeason -> Round; a season belongs to exactly one competition).
///
/// Phase 7.2: the competition model is calendar-driven and monthly -- a
/// season is a calendar-bounded window ([startAt]/[endAt]), not a
/// Round-sequenced concept.
///
/// Pure and immutable; value-comparable.
final class CompetitionSeason {
  const CompetitionSeason._({
    required this.id,
    required this.competitionId,
    required this.label,
    required this.startAt,
    required this.endAt,
  });

  /// Rehydrates a season from already-trusted stored fields (infrastructure
  /// mapper). No validation beyond typing.
  const CompetitionSeason.fromStored({
    required this.id,
    required this.competitionId,
    required this.label,
    required this.startAt,
    required this.endAt,
  });

  /// Creates a new season from validated inputs. [label] is trimmed and
  /// length-checked (1-60 chars). [startAt]/[endAt] must both be UTC
  /// instants with endAt strictly after startAt.
  static Result<CompetitionSeason> create({
    required SeasonId id,
    required CompetitionId competitionId,
    required String label,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return const Result.err(
        AppError.validation(
          'competition.season_label_empty',
          'Season label is required',
        ),
      );
    }
    if (trimmed.length > _maxLabelLength) {
      return const Result.err(
        AppError.validation(
          'competition.season_label_too_long',
          'Season label must be at most $_maxLabelLength characters',
        ),
      );
    }
    if (!startAt.isUtc || !endAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'competition.season_window_not_utc',
          'Season startAt/endAt must be UTC instants',
        ),
      );
    }
    if (!endAt.isAfter(startAt)) {
      return const Result.err(
        AppError.validation(
          'competition.season_window_invalid',
          'Season endAt must be after startAt',
        ),
      );
    }
    return Result.ok(
      CompetitionSeason._(
        id: id,
        competitionId: competitionId,
        label: trimmed,
        startAt: startAt,
        endAt: endAt,
      ),
    );
  }

  static const int _maxLabelLength = 60;

  final SeasonId id;
  final CompetitionId competitionId;
  final String label;
  final DateTime startAt;
  final DateTime endAt;

  @override
  bool operator ==(Object other) =>
      other is CompetitionSeason &&
      other.id == id &&
      other.competitionId == competitionId &&
      other.label == label &&
      other.startAt == startAt &&
      other.endAt == endAt;

  @override
  int get hashCode => Object.hash(id, competitionId, label, startAt, endAt);

  @override
  String toString() =>
      'CompetitionSeason(${id.value}, competition: ${competitionId.value}, '
      '"$label", $startAt - $endAt)';
}
