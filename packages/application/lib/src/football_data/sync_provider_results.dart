import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/ports/league_repository.dart';
import 'package:application/src/football_data/ports/provider_sync_store.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Records a final scoreline for [fixtureId] and scores it -- in production
/// the same `RecordFixtureResult` + `ScoreFixture` pair the admin endpoint
/// runs, under the server's service principal.
typedef ProviderResultRecorder =
    Future<Result<void>> Function({
      required String fixtureId,
      required int homeGoals,
      required int awayGoals,
    });

/// System use-case: record the results of the fixtures the sync added, once
/// the provider reports them finished.
///
/// Only fixtures linked to the provider and still without a result are
/// looked at, and only after [settleTime] from kickoff -- so nothing is asked
/// of the provider while no added match can have ended. Fixtures are grouped
/// by provider competition and Riyadh day, one provider call per group, at
/// most [maxCallsPerRun] per run. A postponed or cancelled match is never
/// given a result; it is logged for an admin. Results the admin already
/// entered are never touched (such fixtures are not pending).
///
/// A finished score is not recorded the first time a provider reports it: a
/// provider can flip a match to finished with a score it corrects a little
/// later (a goal ruled out by VAR, for one). The score is recorded only once
/// the same finished score has been seen unchanged for [confirmAfter]; a
/// changed score starts the wait again. The wait is kept in memory per
/// provider and fixture, so a server restart just starts it over.
///
/// With `apply: false` (shadow mode) nothing is written. Never throws.
final class SyncProviderResults {
  /// Creates the use-case.
  SyncProviderResults({
    required Map<String, FootballDataProvider> providers,
    required ProviderSyncStore store,
    required LeagueRepository leagueRepository,
    required List<ProviderLeagueRule> rules,
    required ProviderResultRecorder recorder,
    this.settleTime = const Duration(minutes: 90),
    this.confirmAfter = const Duration(minutes: 15),
    this.lookback = const Duration(hours: 6),
    this.maxCallsPerRun = 8,
  }) : _providers = providers,
       _store = store,
       _leagues = leagueRepository,
       _rules = rules,
       _recorder = recorder;

  final Map<String, FootballDataProvider> _providers;
  final ProviderSyncStore _store;
  final LeagueRepository _leagues;
  final List<ProviderLeagueRule> _rules;
  final ProviderResultRecorder _recorder;

  /// How long after kickoff a match is first looked up.
  final Duration settleTime;

  /// How far back pending fixtures are still chased.
  final Duration lookback;

  /// How long the same finished score must stand, seen on two runs at least
  /// this far apart, before it is recorded. [Duration.zero] records at once.
  final Duration confirmAfter;

  /// The finished score last seen per `source|fixtureId`, and since when it
  /// has stood.
  final Map<String, _FinishedSighting> _sightings =
      <String, _FinishedSighting>{};

  /// Provider calls allowed in one run.
  final int maxCallsPerRun;

  /// Runs once at [now]; writes only when [apply]. Every provider with a
  /// rule is asked about its own pending fixtures; a fixture linked to two
  /// providers is recorded by whichever reports it finished first (it is no
  /// longer pending for the other).
  Future<Result<ProviderSyncReport>> call({
    required DateTime now,
    required bool apply,
  }) async {
    final nowUtc = now.toUtc();
    final sources = <String>{
      for (final rule in _rules)
        if (_providers.containsKey(rule.source)) rule.source,
    };

    final pendingBySource = <String, List<PendingProviderFixture>>{};
    for (final source in sources) {
      final pendingResult = await _store.fixturesAwaitingResult(
        source: source,
        kickedOffFrom: nowUtc.subtract(lookback),
        kickedOffBefore: nowUtc.subtract(settleTime),
      );
      if (pendingResult is Err<List<PendingProviderFixture>>) {
        return Result.err(pendingResult.error);
      }
      final pending = (pendingResult as Ok<List<PendingProviderFixture>>).value;
      if (pending.isNotEmpty) {
        pendingBySource[source] = pending;
      }
    }
    // Forget the sightings of fixtures that are no longer waiting (recorded,
    // entered by an admin, or past the look-back).
    final waitingKeys = <String>{
      for (final entry in pendingBySource.entries)
        for (final fixture in entry.value) '${entry.key}|${fixture.fixtureId}',
    };
    _sightings.removeWhere((key, _) => !waitingKeys.contains(key));

    if (pendingBySource.isEmpty) {
      return const Result.ok(
        ProviderSyncReport(
          requests: 0,
          applied: 0,
          alreadyKnown: 0,
          skipped: 0,
          notes: <String>[],
        ),
      );
    }

    final leaguesResult = await _leagues.listAll();
    if (leaguesResult is Err<List<League>>) {
      return Result.err(leaguesResult.error);
    }
    final leagueNameById = <String, String>{
      for (final league in (leaguesResult as Ok<List<League>>).value)
        league.id.value: league.name.trim(),
    };
    final ruleFor = <String, ProviderLeagueRule>{
      for (final rule in _rules) '${rule.source}|${rule.leagueName}': rule,
    };

    // Group by provider, competition and Riyadh day: one call covers them.
    // A fixture linked to a provider that does not serve its competition is
    // left to the provider that does.
    final notes = <String>[];
    final groups = <String, List<PendingProviderFixture>>{};
    final groupRule = <String, ProviderLeagueRule>{};
    final groupDay = <String, DateTime>{};
    for (final entry in pendingBySource.entries) {
      for (final fixture in entry.value) {
        final leagueName = leagueNameById[fixture.leagueId];
        final rule = leagueName == null
            ? null
            : ruleFor['${entry.key}|$leagueName'];
        if (rule == null) {
          continue;
        }
        final day = riyadhDayOf(fixture.kickoffAt);
        final key = '${rule.source}|${rule.externalLeagueId}|${isoDay(day)}';
        groups.putIfAbsent(key, () => <PendingProviderFixture>[]).add(fixture);
        groupRule[key] = rule;
        groupDay[key] = day;
      }
    }

    var requests = 0;
    var applied = 0;
    var waiting = 0;
    var skipped = 0;
    final recordedIds = <String>{};
    final exhausted = <String>{};
    final calls = <String, int>{};
    for (final entry in groups.entries) {
      final rule = groupRule[entry.key]!;
      if (exhausted.contains(rule.source)) {
        continue;
      }
      if ((calls[rule.source] ?? 0) >= maxCallsPerRun) {
        notes.add('call budget reached for ${rule.source}; the rest waits');
        exhausted.add(rule.source);
        continue;
      }
      calls[rule.source] = (calls[rule.source] ?? 0) + 1;
      requests++;
      final fetched = await _providers[rule.source]!.matchesOn(
        leagueExternalId: rule.externalLeagueId,
        riyadhDay: groupDay[entry.key]!,
      );
      if (fetched is Err<List<ProviderMatch>>) {
        notes.add('fetch ${entry.key} failed: ${fetched.error.code}');
        if (fetched.error.code == providerQuotaErrorCode) {
          exhausted.add(rule.source);
        }
        continue;
      }
      final byId = <String, ProviderMatch>{
        for (final match in (fetched as Ok<List<ProviderMatch>>).value)
          match.externalId: match,
      };

      for (final fixture in entry.value) {
        if (recordedIds.contains(fixture.fixtureId)) {
          continue;
        }
        // Whatever this run finds, the earlier sighting is taken out; only a
        // finished score puts one back (below).
        final sightingKey = '${rule.source}|${fixture.fixtureId}';
        final previous = _sightings.remove(sightingKey);
        final match = byId[fixture.externalId];
        if (match == null) {
          skipped++;
          notes.add(
            'match ${fixture.externalId} not returned for ${entry.key}',
          );
          continue;
        }
        switch (match.status) {
          case ProviderMatchStatus.postponed:
          case ProviderMatchStatus.cancelled:
            skipped++;
            notes.add(
              'needs admin (${match.status.name}): ${match.homeTeamName} - '
              '${match.awayTeamName}, fixture ${fixture.fixtureId}',
            );
            continue;
          case ProviderMatchStatus.scheduled:
          case ProviderMatchStatus.live:
          case ProviderMatchStatus.unknown:
            waiting++;
            continue;
          case ProviderMatchStatus.finished:
            break;
        }
        final homeGoals = match.homeGoals;
        final awayGoals = match.awayGoals;
        if (homeGoals == null || awayGoals == null) {
          waiting++;
          continue;
        }
        final label =
            '${match.homeTeamName} $homeGoals-$awayGoals '
            '${match.awayTeamName} (fixture ${fixture.fixtureId})';

        // The same finished score must stand for [confirmAfter] before it is
        // recorded; a different score starts the wait again.
        final unchangedSince =
            previous != null &&
                previous.homeGoals == homeGoals &&
                previous.awayGoals == awayGoals
            ? previous.since
            : null;
        final since = unchangedSince ?? nowUtc;
        _sightings[sightingKey] = _FinishedSighting(
          homeGoals,
          awayGoals,
          since,
        );
        if (nowUtc.difference(since) < confirmAfter) {
          waiting++;
          if (unchangedSince == null) {
            notes.add(
              previous == null
                  ? 'finished, confirming for ${confirmAfter.inMinutes} min: '
                        '$label'
                  : 'score changed from '
                        '${previous.homeGoals}-${previous.awayGoals} before it '
                        'was confirmed: $label',
            );
          }
          continue;
        }
        if (!apply) {
          applied++;
          recordedIds.add(fixture.fixtureId);
          notes.add('would record: $label');
          continue;
        }
        final recorded = await _recorder(
          fixtureId: fixture.fixtureId,
          homeGoals: homeGoals,
          awayGoals: awayGoals,
        );
        if (recorded is Err<void>) {
          notes.add('record failed (${recorded.error.code}): $label');
          continue;
        }
        applied++;
        recordedIds.add(fixture.fixtureId);
        _sightings.remove(sightingKey);
        notes.add('recorded: $label');
      }
    }

    return Result.ok(
      ProviderSyncReport(
        requests: requests,
        applied: applied,
        alreadyKnown: waiting,
        skipped: skipped,
        notes: notes,
      ),
    );
  }
}

/// A finished score a provider reported, and since when it has stood.
final class _FinishedSighting {
  const _FinishedSighting(this.homeGoals, this.awayGoals, this.since);

  final int homeGoals;
  final int awayGoals;
  final DateTime since;
}
