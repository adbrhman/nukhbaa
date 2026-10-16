import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One movement of a player's points, with its match's name (batch 146b).
final class PlayerPointEntry {
  /// Creates the movement.
  const PlayerPointEntry({
    required this.id,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kind,
    required this.amount,
    required this.occurredAt,
  });

  /// The ledger entry's id.
  final String id;

  /// The match it belongs to.
  final String fixtureId;

  /// The match's sides, when its schedule is on file.
  final String? homeTeam;

  /// The away side, when on file.
  final String? awayTeam;

  /// The entry kind's wire token (`EntryKind.wireValue`).
  final String kind;

  /// The points it moved (a correction may be negative).
  final int amount;

  /// When it was written (UTC).
  final DateTime occurredAt;
}

/// A player's points in one month: his place in it, when he has one, and
/// every movement of the fixture ledger (`ledger.fixture_point_entries`),
/// the store the boards read since fixtures replaced rounds (audit C-01).
final class PlayerMonthPoints {
  /// Creates the month.
  const PlayerMonthPoints({required this.participantId, required this.entries});

  /// The player's participation in the month, or null when he never
  /// played in it.
  final String? participantId;

  /// The movements, oldest first.
  final List<PlayerPointEntry> entries;

  /// The month's points as its board counts them: match scores and their
  /// corrections (`season_fixture_standings`, migration 0072).
  int get monthPoints => entries
      .where((e) => e.kind != EntryKind.streakBonus.wireValue)
      .fold(0, (int sum, PlayerPointEntry e) => sum + e.amount);

  /// The streak bonuses, which count in the weekly league only (0072).
  int get streakBonus => entries
      .where((e) => e.kind == EntryKind.streakBonus.wireValue)
      .fold(0, (int sum, PlayerPointEntry e) => sum + e.amount);
}

/// Port: a player's points in one month, in one read. Implemented in
/// Infrastructure over `competition.participants`,
/// `ledger.fixture_point_entries` and `competition.fixture_schedules`.
abstract interface class PlayerPointsReader {
  /// The points of [user] in [season].
  Future<Result<PlayerMonthPoints>> pointsOf({
    required UserId user,
    required SeasonId season,
  });
}
