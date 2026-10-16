import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/football_data/follow_provider_kickoff.dart';
import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/ports/league_repository.dart';
import 'package:application/src/football_data/ports/provider_sync_store.dart';
import 'package:application/src/football_data/ports/team_repository.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/rescore_earlier_kickoff.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// System use-case: add the providers' upcoming matches that the rules select
/// to the monthly contest, exactly as an admin would -- a fixture schedule
/// (catalog team names and ids, league), a link to the month's season, and the
/// provider identity so the same match is never added twice.
///
/// Driven by the server scheduler, never by a request. Teams resolve through
/// `external_identity_map` only; a match with an unmapped team is skipped and
/// logged, never guessed by name. A match that kicks off within [minimumLead]
/// is left alone (too late to predict), as is one outside every monthly
/// contest. With `apply: false` (shadow mode) nothing is written and the
/// report says what would have been added.
///
/// Adds fixtures; the only change it makes to one already on the schedule is
/// its kickoff, kept in step with the provider's by [FollowProviderKickoff]
/// (C-03): what it may not move is left for an admin, in the report's
/// `attention`. Never throws.
final class SyncProviderFixtures {
  /// Creates the use-case. [rescoreEarlierKickoff] scores a fixture again
  /// when its kickoff comes earlier after its result; without it (tests that
  /// do not look at it) nothing is scored again.
  SyncProviderFixtures({
    required Map<String, FootballDataProvider> providers,
    required ProviderSyncStore store,
    required LeagueRepository leagueRepository,
    required TeamRepository teamRepository,
    required CompetitionRepository competitionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required IdGenerator idGenerator,
    required List<ProviderLeagueRule> rules,
    this.minimumLead = const Duration(minutes: 30),
    this.duplicateWindow = const Duration(hours: 12),
    this.minimumInterval = const Duration(hours: 1),
    this.daysBySource = const <String, int>{},
    this.kickoffTolerance = const Duration(minutes: 1),
    RescoreEarlierKickoff? rescoreEarlierKickoff,
  }) : _providers = providers,
       _store = store,
       _leagues = leagueRepository,
       _teams = teamRepository,
       _competitions = competitionRepository,
       _schedules = fixtureScheduleRepository,
       _fixturePredictions = fixturePredictionRepository,
       _ids = idGenerator,
       _rules = rules,
       _kickoffs = FollowProviderKickoff(
         fixtureScheduleRepository: fixtureScheduleRepository,
         competitionRepository: competitionRepository,
         rescoreEarlierKickoff: rescoreEarlierKickoff,
         kickoffTolerance: kickoffTolerance,
       );

  final Map<String, FootballDataProvider> _providers;
  final ProviderSyncStore _store;
  final LeagueRepository _leagues;
  final TeamRepository _teams;
  final CompetitionRepository _competitions;
  final FixtureScheduleRepository _schedules;
  final FixturePredictionRepository _fixturePredictions;
  final IdGenerator _ids;
  final List<ProviderLeagueRule> _rules;
  final FollowProviderKickoff _kickoffs;

  /// Matches kicking off sooner than this are not added.
  final Duration minimumLead;

  /// An existing fixture of the same two teams kicking off this close to the
  /// provider's kickoff is taken to be the same match.
  final Duration duplicateWindow;

  /// A run this soon after the last successful one does nothing. The
  /// scheduler starts a run three minutes after every boot, so without
  /// this a burst of redeploys spent a whole provider daily quota on
  /// schedules it had just read.
  final Duration minimumInterval;

  /// How many of the days offered a source is asked about, by source. A
  /// source absent here is asked about every day. A day is seen more than
  /// once before it arrives, so asking a small-quota provider about two
  /// days instead of three still picks up a late schedule change.
  final Map<String, int> daysBySource;

  /// A known fixture whose provider kickoff differs from the stored one by
  /// less than this is left as it is.
  final Duration kickoffTolerance;

  /// Runs every rule over [riyadhDays] at [now]; writes only when [apply].
  Future<Result<ProviderSyncReport>> call({
    required DateTime now,
    required List<DateTime> riyadhDays,
    required bool apply,
  }) async {
    final nowUtc = now.toUtc();

    if (apply) {
      final lastRun = await _store.lastSyncAt(fixturesSyncJob);
      if (lastRun is Ok<DateTime?>) {
        final last = lastRun.value;
        if (last != null && nowUtc.difference(last) < minimumInterval) {
          final minutes = nowUtc.difference(last).inMinutes;
          return Result.ok(
            ProviderSyncReport(
              requests: 0,
              applied: 0,
              alreadyKnown: 0,
              skipped: 0,
              notes: <String>[
                'skipped: the last fixtures sync ran ${minutes}m ago',
              ],
            ),
          );
        }
      }
    }

    final leaguesResult = await _leagues.listAll();
    if (leaguesResult is Err<List<League>>) {
      return Result.err(leaguesResult.error);
    }
    final teamsResult = await _teams.listAll();
    if (teamsResult is Err<List<Team>>) {
      return Result.err(teamsResult.error);
    }
    final seasonsResult = await _competitions.listMonthlySeasons();
    if (seasonsResult is Err<List<CompetitionSeason>>) {
      return Result.err(seasonsResult.error);
    }

    final leagueByName = <String, League>{
      for (final league in (leaguesResult as Ok<List<League>>).value)
        league.name.trim(): league,
    };
    final teamById = <String, Team>{
      for (final team in (teamsResult as Ok<List<Team>>).value)
        team.id.value: team,
    };
    final months = (seasonsResult as Ok<List<CompetitionSeason>>).value
        .where(isMonthlyContest)
        .toList(growable: false);

    final notes = <String>[];
    final attention = <ProviderSyncAttention>[];
    final nextOrder = <String, int>{};
    var requests = 0;
    var applied = 0;
    var known = 0;
    var skipped = 0;

    final exhausted = <String>{};
    for (final rule in _rules) {
      final provider = _providers[rule.source];
      if (provider == null) {
        notes.add('no provider configured for ${rule.source}');
        continue;
      }
      if (exhausted.contains(rule.source)) {
        continue;
      }
      final league = leagueByName[rule.leagueName];
      if (league == null) {
        notes.add('league not in catalog: ${rule.leagueName}');
        continue;
      }
      final pairName = rule.bothFromLeagueName;
      final pairLeague = pairName == null ? null : leagueByName[pairName];
      if (pairName != null && pairLeague == null) {
        notes.add('league not in catalog: $pairName');
        continue;
      }

      final dayCap = daysBySource[rule.source] ?? riyadhDays.length;
      for (var dayIndex = 0; dayIndex < riyadhDays.length; dayIndex++) {
        if (dayIndex >= dayCap) {
          break;
        }
        final day = riyadhDays[dayIndex];
        requests++;
        final fetched = await provider.matchesOn(
          leagueExternalId: rule.externalLeagueId,
          riyadhDay: day,
        );
        if (fetched is Err<List<ProviderMatch>>) {
          notes.add(
            'fetch ${rule.externalLeagueId} ${isoDay(day)} failed: '
            '${fetched.error.code}',
          );
          if (fetched.error.code == providerQuotaErrorCode) {
            // This provider is done for the run; the others carry on.
            exhausted.add(rule.source);
            break;
          }
          continue;
        }

        final fetchedMatches = (fetched as Ok<List<ProviderMatch>>).value;

        // Three categories are handled:
        // 1. future scheduled matches may be added normally (outside
        //    [minimumLead] only);
        // 2. live/finished matches may adopt an already-existing fixture so
        //    result sync can later record and score it. We never create a new
        //    fixture after kickoff;
        // 3. a match already on the schedule keeps its kickoff in step with
        //    the provider's (C-03), however close it is.
        final candidates = fetchedMatches
            .where(
              (match) =>
                  rule.admits(match) &&
                  (match.status == ProviderMatchStatus.scheduled ||
                      match.kickoffAt.isBefore(nowUtc)),
            )
            .toList(growable: false);

        if (candidates.isEmpty) {
          continue;
        }

        final teamIdsResult = await _store.canonicalIds(
          source: rule.source,
          table: 'team',
          externalIds: [
            for (final match in candidates) ...[
              match.homeTeamExternalId,
              match.awayTeamExternalId,
            ],
          ],
        );
        if (teamIdsResult is Err<Map<String, String>>) {
          notes.add('team lookup failed: ${teamIdsResult.error.code}');
          continue;
        }
        final fixtureIdsResult = await _store.canonicalIds(
          source: rule.source,
          table: 'fixture',
          externalIds: [for (final match in candidates) match.externalId],
        );
        if (fixtureIdsResult is Err<Map<String, String>>) {
          notes.add('fixture lookup failed: ${fixtureIdsResult.error.code}');
          continue;
        }
        final teamIds = (teamIdsResult as Ok<Map<String, String>>).value;
        final fixtureIds = (fixtureIdsResult as Ok<Map<String, String>>).value;

        for (final match in candidates) {
          final knownId = fixtureIds[match.externalId];
          if (knownId != null) {
            known++;
            if (match.status == ProviderMatchStatus.scheduled ||
                match.status == ProviderMatchStatus.live ||
                match.status == ProviderMatchStatus.finished) {
              final moved = await _kickoffs(
                fixtureId: knownId,
                match: match,
                homeTeamId: teamIds[match.homeTeamExternalId],
                awayTeamId: teamIds[match.awayTeamExternalId],
                nowUtc: nowUtc,
                apply: apply,
                attention: attention,
                months: months,
              );
              if (moved != null) {
                notes.add(moved);
              }
            }
            continue;
          }
          if (match.status == ProviderMatchStatus.scheduled &&
              !match.kickoffAt.isAfter(nowUtc.add(minimumLead))) {
            // Too late to predict: a new match this close is not added.
            continue;
          }
          final home = teamById[teamIds[match.homeTeamExternalId]];
          final away = teamById[teamIds[match.awayTeamExternalId]];
          if (pairLeague != null && (home == null || away == null)) {
            // An unmapped side cannot be a club of the paired league: this
            // tie is simply not wanted, not a mapping problem.
            skipped++;
            continue;
          }
          if (home == null || away == null) {
            skipped++;
            notes.add(
              'unmapped team: ${match.homeTeamName} '
              '(${match.homeTeamExternalId}) vs ${match.awayTeamName} '
              '(${match.awayTeamExternalId})',
            );
            continue;
          }
          if (home.blocked || away.blocked) {
            // A club whose matches never appear (migration 0174, decided by
            // the owner 2026-10-16), whatever the competition: skipped
            // before anything is written, which the schedule would refuse.
            skipped++;
            notes.add('blocked club: ${home.name} - ${away.name}');
            continue;
          }
          if (pairLeague != null &&
              (home.leagueId != pairLeague.id ||
                  away.leagueId != pairLeague.id)) {
            skipped++;
            continue;
          }
          final month = monthContaining(months, match.kickoffAt);
          if (month == null) {
            skipped++;
            notes.add(
              'no monthly contest for ${home.name} - ${away.name} '
              '${match.kickoffAt.toIso8601String()}',
            );
            continue;
          }

          final label =
              '${home.name} - ${away.name} '
              '${match.kickoffAt.toIso8601String()} -> ${month.label}';

          // A provider match that has already started can only adopt an
          // existing fixture. Never add a brand-new prediction fixture after
          // kickoff.
          final existingResult = await _store.findExistingFixture(
            homeTeamId: home.id.value,
            awayTeamId: away.id.value,
            homeTeamName: home.name,
            awayTeamName: away.name,
            kickoffAt: match.kickoffAt.toUtc(),
            from: match.kickoffAt.toUtc().subtract(duplicateWindow),
            to: match.kickoffAt.toUtc().add(duplicateWindow),
          );
          if (existingResult is Err<String?>) {
            notes.add(
              'duplicate check failed (${existingResult.error.code}): $label',
            );
            continue;
          }
          final existing = (existingResult as Ok<String?>).value;
          if (existing != null) {
            // Already on the schedule (added by hand): adopt it so its result
            // is fetched too, instead of adding a second copy.
            known++;
            if (!apply) {
              notes.add('would adopt existing $existing: $label');
              continue;
            }
            final adopted = await _store.link(
              source: rule.source,
              table: 'fixture',
              externalId: match.externalId,
              canonicalId: existing,
            );
            notes.add(
              adopted is Err<void>
                  ? 'adopt failed (${adopted.error.code}): $label'
                  : 'adopted existing $existing: $label',
            );
            continue;
          }

          if (match.status != ProviderMatchStatus.scheduled) {
            // Past kickoff with no fixture to adopt: adding it now
            // would put a card nobody can predict in the contest.
            skipped++;
            continue;
          }

          if (!apply) {
            applied++;
            notes.add('would add: $label');
            continue;
          }

          final added = await _add(
            source: rule.source,
            match: match,
            home: home,
            away: away,
            league: league,
            month: month,
            nextOrder: nextOrder,
          );
          if (added is Err<void>) {
            notes.add('add failed (${added.error.code}): $label');
            continue;
          }
          applied++;
          notes.add('added: $label');
        }
      }
    }

    if (apply) {
      await _store.markSyncAt(fixturesSyncJob, nowUtc);
    }

    return Result.ok(
      ProviderSyncReport(
        requests: requests,
        applied: applied,
        alreadyKnown: known,
        skipped: skipped,
        notes: notes,
        attention: attention,
      ),
    );
  }

  Future<Result<void>> _add({
    required String source,
    required ProviderMatch match,
    required Team home,
    required Team away,
    required League league,
    required CompetitionSeason month,
    required Map<String, int> nextOrder,
  }) async {
    final fixtureResult = FixtureRef.tryParse(_ids.newUuid());
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    final scheduleResult = FixtureSchedule.create(
      fixture: fixture,
      homeTeam: home.name,
      awayTeam: away.name,
      kickoffAt: match.kickoffAt.toUtc(),
      homeTeamId: home.id,
      awayTeamId: away.id,
      leagueId: league.id,
    );
    if (scheduleResult is Err<FixtureSchedule>) {
      return Result.err(scheduleResult.error);
    }

    var order = nextOrder[month.id.value];
    if (order == null) {
      final listed = await _fixturePredictions.listSeasonFixtures(month.id);
      if (listed is Err<List<FixtureRef>>) {
        return Result.err(listed.error);
      }
      order = (listed as Ok<List<FixtureRef>>).value.length;
    }
    final linkResult = SeasonFixture.create(
      seasonId: month.id,
      fixture: fixture,
      displayOrder: order,
    );
    if (linkResult is Err<SeasonFixture>) {
      return Result.err(linkResult.error);
    }

    // Schedule first (a season link needs it), then the provider identity so
    // a later run never adds this match again, then the contest link.
    final saved = await _schedules.upsert(
      (scheduleResult as Ok<FixtureSchedule>).value,
    );
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }
    final identity = await _store.link(
      source: source,
      table: 'fixture',
      externalId: match.externalId,
      canonicalId: fixture.value,
    );
    if (identity is Err<void>) {
      return Result.err(identity.error);
    }
    final linked = await _fixturePredictions.linkFixtureToSeason(
      (linkResult as Ok<SeasonFixture>).value,
    );
    if (linked is Err<void>) {
      return Result.err(linked.error);
    }
    nextOrder[month.id.value] = order + 1;
    return const Result.ok(null);
  }
}
