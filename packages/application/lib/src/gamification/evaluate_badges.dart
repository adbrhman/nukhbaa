import 'package:application/src/common/id_generator.dart';
import 'package:application/src/gamification/ports/badge_progress_reader.dart';
import 'package:application/src/gamification/ports/gamification_event_sink.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: awards the badges players have earned (P2-6).
///
/// Reads every player's tally and the badges already held
/// (`BadgeProgressReader`), and for each badge the catalog says is earned but
/// not yet held writes one `badge_unlocked` event. The event IS the badge:
/// there is no badge table and no points are written.
///
/// **Idempotent and replayable.** A badge event is keyed on the user and the
/// code, so a second run, a run that overlaps a slow first one, or a badge
/// already held that the reader failed to see, writes nothing new. Nothing is
/// ever updated or removed: a badge that was earned stays earned even if the
/// counts behind it could later fall.
///
/// **`occurred_at` is the moment of the award** ([call]'s `now`). Unlike the
/// weekly-league standing, no ordering depends on it.
///
/// **A sink failure is not ignored.** The event sink is tier-3 for the acts
/// that emit into it, but here the event is the work. One player's failure
/// does not stop the others: the run carries on, and once it has finished it
/// returns the first failure. What was written stays written, and the next
/// run picks up the rest.
///
/// Never throws; returns a typed [Result] with the number of badges awarded.
final class EvaluateBadges {
  /// Creates the use-case over its collaborators.
  const EvaluateBadges({
    required BadgeProgressReader progress,
    required GamificationEventSink events,
    required IdGenerator idGenerator,
  }) : _progress = progress,
       _events = events,
       _ids = idGenerator;

  final BadgeProgressReader _progress;
  final GamificationEventSink _events;
  final IdGenerator _ids;

  /// Awards what is earned as of [now]; returns how many badges it awarded.
  Future<Result<int>> call({required DateTime now}) async {
    final readResult = await _progress.readAll();
    if (readResult is Err<List<UserBadgeStanding>>) {
      return Result.err(readResult.error);
    }
    final standings = (readResult as Ok<List<UserBadgeStanding>>).value;

    var awarded = 0;
    AppError? firstFailure;
    for (final standing in standings) {
      for (final code in BadgeCode.earnedBy(standing.progress)) {
        if (standing.unlocked.contains(code)) {
          continue;
        }
        final built = GamificationEvent.badgeUnlocked(
          id: _ids.newUuid(),
          userId: standing.userId,
          code: code,
          occurredAt: now,
        );
        if (built is Err<GamificationEvent>) {
          firstFailure ??= built.error;
          continue;
        }
        final recorded = await _events.record(
          (built as Ok<GamificationEvent>).value,
        );
        if (recorded is Err<void>) {
          firstFailure ??= recorded.error;
          continue;
        }
        awarded++;
      }
    }

    final failure = firstFailure;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(awarded);
  }
}
