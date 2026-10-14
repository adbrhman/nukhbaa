import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:domain/domain.dart';

/// How the automatic provider sync behaves.
enum ProviderSyncMode {
  /// Nothing is fetched.
  off,

  /// Everything is fetched and logged; nothing is written.
  shadow,

  /// Fixtures are added and results recorded (and scored).
  on;

  /// Parses `NUKHBA_PROVIDER_SYNC`; anything unrecognised is [off].
  static ProviderSyncMode parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'shadow':
        return ProviderSyncMode.shadow;
      case 'on':
        return ProviderSyncMode.on;
      default:
        return ProviderSyncMode.off;
    }
  }
}

/// Which matches of one provider competition the sync adds.
final class ProviderLeagueRule {
  /// Creates the rule.
  const ProviderLeagueRule({
    required this.source,
    required this.externalLeagueId,
    required this.leagueName,
    this.clubs = const <String>{},
    this.bothFromLeagueName,
  });

  /// The provider that serves this competition (`highlightly`,
  /// `football-data`): its adapter answers the calls, and its name is the
  /// identity-map source for the competition's teams and fixtures.
  final String source;

  /// The provider's competition id (or code).
  final String externalLeagueId;

  /// The competition's name in `football_data.leagues`; fixtures are filed
  /// under that league.
  final String leagueName;

  /// Provider team ids; a match is added when either side is one of them.
  /// Empty means every match.
  final Set<String> clubs;

  /// When set, a match is added only if both sides belong to this catalog
  /// league (e.g. League Cup ties between Premier League clubs).
  final String? bothFromLeagueName;

  /// Whether the club filter admits [match] (the league filter is applied
  /// separately, on catalog teams).
  bool admits(ProviderMatch match) =>
      clubs.isEmpty ||
      clubs.contains(match.homeTeamExternalId) ||
      clubs.contains(match.awayTeamExternalId);
}

/// The Riyadh calendar day (UTC+3, no daylight saving) of [instant], as a UTC
/// midnight carrying that day's year, month and day.
DateTime riyadhDayOf(DateTime instant) {
  final local = instant.toUtc().add(const Duration(hours: 3));
  return DateTime.utc(local.year, local.month, local.day);
}

/// `yyyy-mm-dd` of a day returned by [riyadhDayOf].
String isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// `yyyy-mm-dd hh:mm` of [instant] on the Riyadh clock (UTC+3), for what an
/// admin reads.
String riyadhClock(DateTime instant) {
  final local = instant.toUtc().add(const Duration(hours: 3));
  return '${isoDay(riyadhDayOf(instant))} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

final RegExp _monthlyLabel = RegExp(r'^\d{2}/\d{4}$');

/// Whether [season] is a monthly contest (`MM/yyyy`), not a sporting season.
bool isMonthlyContest(CompetitionSeason season) =>
    _monthlyLabel.hasMatch(season.label);

/// The monthly contest of [months] that [instant] falls in, or null.
CompetitionSeason? monthContaining(
  List<CompetitionSeason> months,
  DateTime instant,
) {
  final at = instant.toUtc();
  for (final month in months) {
    if (!at.isBefore(month.startAt.toUtc()) &&
        at.isBefore(month.endAt.toUtc())) {
      return month;
    }
  }
  return null;
}

/// A match one sync run could not settle by itself and leaves for an admin
/// (audit C-03): a kickoff it may not move, one it failed to move, a fixture
/// it could not score again, a match postponed or cancelled. The server
/// keeps each one in the error log, which tells the admins; a note reaches
/// only the container log.
final class ProviderSyncAttention {
  /// Creates the entry.
  const ProviderSyncAttention({
    required this.code,
    required this.match,
    required this.message,
  });

  /// What kind of matter it is (`provider_sync.kickoff_put_back_late`, ...).
  final String code;

  /// The match, `home - away`: one error-log entry per match and [code].
  final String match;

  /// What happened and what to do, in Arabic, for the admin.
  final String message;
}

/// What one sync run did, for the server log.
final class ProviderSyncReport {
  /// Creates the report.
  const ProviderSyncReport({
    required this.requests,
    required this.applied,
    required this.alreadyKnown,
    required this.skipped,
    required this.notes,
    this.attention = const <ProviderSyncAttention>[],
  });

  /// Provider calls made.
  final int requests;

  /// Fixtures added / results recorded (or that would be, in shadow mode).
  final int applied;

  /// Matches already handled on an earlier run.
  final int alreadyKnown;

  /// Matches passed over (unmapped team, no contest month, not finished...).
  final int skipped;

  /// One line per notable event.
  final List<String> notes;

  /// The matches left for an admin, each kept in the error log by the
  /// scheduler when the sync writes ([ProviderSyncAttention]).
  final List<ProviderSyncAttention> attention;
}
