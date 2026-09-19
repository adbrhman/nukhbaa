import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/ports/league_repository.dart';
import 'package:application/src/football_data/ports/live_score_board.dart';
import 'package:application/src/football_data/ports/provider_sync_store.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What one live refresh did: how many fixtures now show a running score,
/// and which of them the provider reports finished -- the scheduler starts a
/// results check at once instead of waiting for the next results tick.
final class LiveScoreRefresh {
  /// Creates the report.
  const LiveScoreRefresh({required this.updated, required this.finished});

  /// Fixtures whose score the board now holds.
  final int updated;

  /// Fixture ids the provider reports finished in this run.
  final List<String> finished;
}

/// System use-case: refresh the running scores of the synced fixtures that
/// are in play, for display in the fixtures feed.
///
/// Only providers in `liveSources` are asked (a provider with a small daily
/// quota is left out on purpose), and only for competitions that have a
/// provider-linked fixture which kicked off within [window] and has no
/// recorded result -- so between matches it costs nothing. One call per
/// competition and Riyadh day. Nothing is recorded or scored here.
///
/// Never throws.
final class RefreshLiveScores {
  /// Creates the use-case.
  const RefreshLiveScores({
    required Map<String, FootballDataProvider> providers,
    required ProviderSyncStore store,
    required LeagueRepository leagueRepository,
    required List<ProviderLeagueRule> rules,
    required LiveScoreBoard board,
    required Set<String> liveSources,
    this.window = const Duration(minutes: 180),
    this.maxCallsPerRun = 6,
  }) : _providers = providers,
       _store = store,
       _leagues = leagueRepository,
       _rules = rules,
       _board = board,
       _liveSources = liveSources;

  final Map<String, FootballDataProvider> _providers;
  final ProviderSyncStore _store;
  final LeagueRepository _leagues;
  final List<ProviderLeagueRule> _rules;
  final LiveScoreBoard _board;
  final Set<String> _liveSources;

  /// How long after kickoff a fixture is still considered possibly in play.
  final Duration window;

  /// Provider calls allowed in one run.
  final int maxCallsPerRun;

  /// Runs once at [now]; reports the scores written and the fixtures the
  /// provider now reports finished.
  Future<Result<LiveScoreRefresh>> call({required DateTime now}) async {
    final nowUtc = now.toUtc();
    final sources = <String>{
      for (final rule in _rules)
        if (_liveSources.contains(rule.source) &&
            _providers.containsKey(rule.source))
          rule.source,
    };
    if (sources.isEmpty) {
      return const Result.ok(
        LiveScoreRefresh(updated: 0, finished: <String>[]),
      );
    }

    AppError? failure;
    final pendingBySource = <String, List<PendingProviderFixture>>{};
    for (final source in sources) {
      final pending = await _store.fixturesAwaitingResult(
        source: source,
        kickedOffFrom: nowUtc.subtract(window),
        kickedOffBefore: nowUtc,
      );
      if (pending is Err<List<PendingProviderFixture>>) {
        // One source timing out must not blind the others this tick.
        failure = pending.error;
        continue;
      }
      final list = (pending as Ok<List<PendingProviderFixture>>).value;
      if (list.isNotEmpty) {
        pendingBySource[source] = list;
      }
    }
    if (pendingBySource.isEmpty) {
      final lost = failure;
      return lost == null
          ? const Result.ok(LiveScoreRefresh(updated: 0, finished: <String>[]))
          : Result.err(lost);
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

    final fresh = <String, LiveScore>{};
    final finishedIds = <String>[];
    final gone = <String>[];
    var calls = 0;
    for (final entry in groups.entries) {
      if (calls >= maxCallsPerRun) {
        break;
      }
      calls++;
      final rule = groupRule[entry.key]!;
      final fetched = await _providers[rule.source]!.matchesOn(
        leagueExternalId: rule.externalLeagueId,
        riyadhDay: groupDay[entry.key]!,
      );
      if (fetched is Err<List<ProviderMatch>>) {
        if (fetched.error.code == providerQuotaErrorCode) {
          break;
        }
        continue;
      }
      final byId = <String, ProviderMatch>{
        for (final match in (fetched as Ok<List<ProviderMatch>>).value)
          match.externalId: match,
      };
      for (final fixture in entry.value) {
        final match = byId[fixture.externalId];
        if (match == null) {
          continue;
        }
        switch (match.status) {
          case ProviderMatchStatus.live:
            {
              final home = match.currentHomeGoals;
              final away = match.currentAwayGoals;
              if (home != null && away != null) {
                fresh[fixture.fixtureId] = LiveScore(
                  homeGoals: home,
                  awayGoals: away,
                  minute: match.minute,
                  finished: false,
                  updatedAt: nowUtc,
                );
              }
            }
          case ProviderMatchStatus.finished:
            {
              final home = match.homeGoals;
              final away = match.awayGoals;
              if (home != null && away != null) {
                fresh[fixture.fixtureId] = LiveScore(
                  homeGoals: home,
                  awayGoals: away,
                  finished: true,
                  updatedAt: nowUtc,
                );
                finishedIds.add(fixture.fixtureId);
              }
            }
          case ProviderMatchStatus.scheduled:
          case ProviderMatchStatus.postponed:
          case ProviderMatchStatus.cancelled:
          case ProviderMatchStatus.unknown:
            gone.add(fixture.fixtureId);
        }
      }
    }

    _board
      ..remove(gone)
      ..put(fresh);
    return Result.ok(
      LiveScoreRefresh(updated: fresh.length, finished: finishedIds),
    );
  }
}
