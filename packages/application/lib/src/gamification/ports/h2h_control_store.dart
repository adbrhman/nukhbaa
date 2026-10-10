import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the admin's controls over the head-to-head league (migration
/// 0101): the settings row, the days the system must not approve by
/// itself, late seats, and the log of every admin action.
///
/// Backed by `PostgresH2hControlStore`. It stores; the rules of what may be
/// changed and when live in the use-cases. Nothing here touches a point.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient]; a database refusal is an [ErrorKind.invariant].
abstract interface class H2hControlStore {
  /// The settings as they stand.
  Future<Result<H2hSettings>> settings();

  /// Replaces the settings, recording who did it.
  Future<Result<void>> saveSettings({
    required bool autoApprove,
    required int leadHours,
    required int minActiveDays,
    required UserId by,
  });

  /// The excluded Riyadh days from [from] through [through], inclusive.
  Future<Result<Set<DateTime>>> excludedDays({
    required DateTime from,
    required DateTime through,
  });

  /// Excludes [day]; false when it already was.
  Future<Result<bool>> exclude({required DateTime day, required UserId by});

  /// Lifts the exclusion of [day]; false when there was none.
  Future<Result<bool>> include(DateTime day);

  /// Seats [userId] in the empty [slot] of [leagueId] for [monthStart]. A
  /// taken slot, a player already seated that month or a slot outside the
  /// group is refused by the database as an [ErrorKind.invariant].
  Future<Result<void>> addSeat({
    required H2hLeagueId leagueId,
    required DateTime monthStart,
    required UserId userId,
    required int slot,
  });

  /// Writes one line of the admin log.
  Future<Result<void>> record({
    required String id,
    required H2hAdminActionKind action,
    required UserId? by,
    required Map<String, Object?> detail,
  });

  /// The latest [limit] lines of the admin log, newest first.
  Future<Result<List<H2hAdminAction>>> recentActions(int limit);
}

/// The admin settings of the league.
final class H2hSettings {
  /// Creates settings.
  const H2hSettings({
    required this.autoApprove,
    required this.leadHours,
    required this.minActiveDays,
    this.updatedBy,
    this.updatedAt,
  });

  /// The rules of 0100, in force until an admin changes them.
  static const H2hSettings defaults = H2hSettings(
    autoApprove: true,
    leadHours: 24,
    minActiveDays: H2hLeaguePolicy.minActiveDays,
  );

  /// The fewest and most hours ahead the system may approve a day.
  static const int minLeadHours = 1;

  /// See [minLeadHours]: the system never looks further than a day ahead.
  static const int maxLeadHours = 24;

  /// The fewest active days the next draw may require.
  static const int minActiveDaysFloor = 1;

  /// The most active days the next draw may require.
  static const int minActiveDaysCeiling = 28;

  /// Whether the system approves regular days by itself.
  final bool autoApprove;

  /// How long before a day's first kickoff the system may approve it.
  final int leadHours;

  /// Days of predictions in a month that put a player into the next draw.
  final int minActiveDays;

  /// Who changed them last, or null for the defaults.
  final UserId? updatedBy;

  /// When they were changed last.
  final DateTime? updatedAt;
}

/// What an admin did.
enum H2hAdminActionKind {
  /// Saved the settings.
  settingsSaved('settings_saved'),

  /// Kept a day from automatic approval.
  dayExcluded('day_excluded'),

  /// Lifted that.
  dayIncluded('day_included'),

  /// Approved a round.
  roundApproved('round_approved'),

  /// Withdrew a round.
  roundWithdrawn('round_withdrawn'),

  /// Seated a late player.
  seatAdded('seat_added'),

  /// Ran the league's scheduled jobs at once.
  jobsRun('jobs_run'),

  /// Started the pilot.
  pilotStarted('pilot_started');

  const H2hAdminActionKind(this.wireName);

  /// The stored and sent value.
  final String wireName;

  /// The kind stored as [raw], or null when this build does not know it.
  static H2hAdminActionKind? ofWire(String? raw) {
    for (final kind in values) {
      if (kind.wireName == raw) {
        return kind;
      }
    }
    return null;
  }
}

/// One line of the admin log.
final class H2hAdminAction {
  /// Creates a line.
  const H2hAdminAction({
    required this.id,
    required this.action,
    required this.actor,
    required this.detail,
    required this.actedAt,
  });

  /// The line.
  final String id;

  /// What was done.
  final H2hAdminActionKind action;

  /// Who did it, or null for the system.
  final UserId? actor;

  /// What it was done to.
  final Map<String, Object?> detail;

  /// When.
  final DateTime actedAt;
}
