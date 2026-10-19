import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/ports/match_details.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:shared/shared.dart';

/// What one run of [SyncMatchDetails] did.
final class MatchDetailsReport {
  /// Creates the report.
  const MatchDetailsReport({
    required this.requests,
    required this.saved,
    required this.notFound,
    required this.notes,
    this.pending = 0,
  });

  /// Nothing to do.
  static const MatchDetailsReport none = MatchDetailsReport(
    requests: 0,
    saved: 0,
    notFound: 0,
    notes: <String>[],
  );

  /// Provider requests spent.
  final int requests;

  /// Matches whose details were stored.
  final int saved;

  /// Fixtures the provider has no match for, stored as such.
  final int notFound;

  /// What happened, for the log.
  final List<String> notes;

  /// Finished fixtures still without details that the run looked at.
  final int pending;
}

/// System use-case: read the story of each finished match -- its goals with
/// their minutes, cards, VAR decisions, the half-time score -- once, for the
/// match details page (2026-10-19, on the model of Sports Mole). Display
/// only: nothing here scores anything or touches a result.
///
/// A fixture is looked at once its result is recorded, [settleTime] after
/// kickoff, and until [lookback] after it. A fixture that came from the
/// details provider carries its match id; any other is found in the
/// provider's list of its league's matches that day ([leagueIds], one call
/// per league and Riyadh day): the match kicking off within
/// [kickoffTolerance] of it, or, when several do, the one that ended on the
/// recorded score. The score is not asked of a single candidate, so a match
/// whose recorded result a feed got wrong (a goal ruled out by VAR) is still
/// found. A fixture with no candidate is stored as not found and not asked
/// about again; one the provider has not finished yet is asked again on a
/// later run. At most [maxCallsPerRun] requests a run. Never throws.
final class SyncMatchDetails {
  /// Creates the use-case. [lister] lists the provider's matches of a
  /// league and day; [leagueIds] maps an app league name to the provider's
  /// league id.
  const SyncMatchDetails({
    required MatchDetailsStore store,
    required MatchDetailsSource source,
    required FootballDataProvider lister,
    required Map<String, String> leagueIds,
    this.settleTime = const Duration(hours: 2, minutes: 15),
    this.lookback = const Duration(days: 3),
    this.kickoffTolerance = const Duration(minutes: 10),
    this.maxCallsPerRun = 8,
  }) : _store = store,
       _source = source,
       _lister = lister,
       _leagueIds = leagueIds;

  final MatchDetailsStore _store;
  final MatchDetailsSource _source;
  final FootballDataProvider _lister;
  final Map<String, String> _leagueIds;

  /// How long after kickoff a match is first looked up.
  final Duration settleTime;

  /// How long after kickoff a match is still looked up.
  final Duration lookback;

  /// How far apart two kickoffs may be and still be the same match.
  final Duration kickoffTolerance;

  /// Provider requests allowed in one run.
  final int maxCallsPerRun;

  /// Runs once at [now].
  Future<Result<MatchDetailsReport>> call({required DateTime now}) async {
    final nowUtc = now.toUtc();
    final pendingResult = await _store.pending(
      source: _source.source,
      kickedOffFrom: nowUtc.subtract(lookback),
      kickedOffBefore: nowUtc.subtract(settleTime),
    );
    if (pendingResult is Err<List<PendingMatchDetails>>) {
      return Result.err(pendingResult.error);
    }
    final pending = (pendingResult as Ok<List<PendingMatchDetails>>).value;
    if (pending.isEmpty) {
      return const Result.ok(MatchDetailsReport.none);
    }

    var calls = 0;
    var saved = 0;
    var notFound = 0;
    final notes = <String>[];
    final lists = <String, List<ProviderMatch>>{};

    for (final fixture in pending) {
      if (calls >= maxCallsPerRun) {
        notes.add('call budget reached; the rest waits');
        break;
      }
      var matchId = fixture.externalMatchId;
      if (matchId == null) {
        final leagueId = _leagueIds[fixture.leagueName.trim()];
        if (leagueId == null) {
          final note = 'no provider league for "${fixture.leagueName}"';
          if (!notes.contains(note)) {
            notes.add(note);
          }
          continue;
        }
        final day = riyadhDayOf(fixture.kickoffAt);
        final key = '$leagueId|${isoDay(day)}';
        var list = lists[key];
        if (list == null) {
          calls++;
          final fetched = await _lister.matchesOn(
            leagueExternalId: leagueId,
            riyadhDay: day,
          );
          if (fetched is Err<List<ProviderMatch>>) {
            notes.add('list $key failed: ${fetched.error.code}');
            if (fetched.error.code == providerQuotaErrorCode) {
              break;
            }
            continue;
          }
          list = (fetched as Ok<List<ProviderMatch>>).value;
          lists[key] = list;
        }
        final picked = _pick(list, fixture);
        if (picked.wait) {
          notes.add('${fixture.fixtureId}: a match at its kickoff is not over');
          continue;
        }
        final candidate = picked.match;
        if (candidate == null) {
          final stored = await _store.save(
            MatchDetails.notFound(
              fixtureId: fixture.fixtureId,
              source: _source.source,
              fetchedAt: nowUtc,
            ),
          );
          if (stored is Ok<void>) {
            notFound++;
            notes.add('no match for fixture ${fixture.fixtureId} in $key');
          }
          continue;
        }
        if (candidate.status != ProviderMatchStatus.finished) {
          notes.add('${candidate.externalId} is not over in the list');
          continue;
        }
        matchId = candidate.externalId;
        if (calls >= maxCallsPerRun) {
          notes.add('call budget reached; the rest waits');
          break;
        }
      }

      calls++;
      final read = await _source.details(
        externalMatchId: matchId,
        fixtureId: fixture.fixtureId,
      );
      if (read is Err<MatchDetails?>) {
        notes.add('details of $matchId failed: ${read.error.code}');
        if (read.error.code == providerQuotaErrorCode) {
          break;
        }
        continue;
      }
      final details = (read as Ok<MatchDetails?>).value;
      if (details == null) {
        notes.add('details of $matchId: the match is not over');
        continue;
      }
      final stored = await _store.save(details);
      if (stored is Err<void>) {
        notes.add('save of ${fixture.fixtureId} failed: ${stored.error.code}');
        continue;
      }
      saved++;
    }

    return Result.ok(
      MatchDetailsReport(
        requests: calls,
        saved: saved,
        notFound: notFound,
        notes: notes,
        pending: pending.length,
      ),
    );
  }

  /// The provider's match for [fixture] in [list]: the only one kicking off
  /// with it, or among several the only one that ended on its score; [wait]
  /// while several kick off with it and one of them is not over.
  ({ProviderMatch? match, bool wait}) _pick(
    List<ProviderMatch> list,
    PendingMatchDetails fixture,
  ) {
    final sameKickoff = <ProviderMatch>[
      for (final match in list)
        if (match.kickoffAt
                .toUtc()
                .difference(fixture.kickoffAt.toUtc())
                .abs() <=
            kickoffTolerance)
          match,
    ];
    if (sameKickoff.isEmpty) {
      return (match: null, wait: false);
    }
    if (sameKickoff.length == 1) {
      return (match: sameKickoff.single, wait: false);
    }
    if (sameKickoff.any(
      (match) => match.status != ProviderMatchStatus.finished,
    )) {
      return (match: null, wait: true);
    }
    final sameScore = <ProviderMatch>[
      for (final match in sameKickoff)
        if (match.homeGoals == fixture.homeGoals &&
            match.awayGoals == fixture.awayGoals)
          match,
    ];
    return (
      match: sameScore.length == 1 ? sameScore.single : null,
      wait: false,
    );
  }
}
