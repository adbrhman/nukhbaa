import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/ports/league_repository.dart';
import 'package:application/src/football_data/ports/provider_sync_store.dart';
import 'package:application/src/football_data/ports/team_repository.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// System use-case: add the provider's upcoming matches that the rules select
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
/// Additive only. Never throws.
final class SyncProviderFixtures {
  /// Creates the use-case.
  const SyncProviderFixtures({
    required FootballDataProvider provider,
    required ProviderSyncStore store,
    required LeagueRepository leagueRepository,
    required TeamRepository teamRepository,
    required CompetitionRepository competitionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required IdGenerator idGenerator,
    required List<ProviderLeagueRule> rules,
    required String source,
    this.minimumLead = const Duration(minutes: 30),
  }) : _provider = provider,
       _store = store,
       _leagues = leagueRepository,
       _teams = teamRepository,
       _competitions = competitionRepository,
       _schedules = fixtureScheduleRepository,
       _fixturePredictions = fixturePredictionRepository,
       _ids = idGenerator,
       _rules = rules,
       _source = source;

  final FootballDataProvider _provider;
  final ProviderSyncStore _store;
  final LeagueRepository _leagues;
  final TeamRepository _teams;
  final CompetitionRepository _competitions;
  final FixtureScheduleRepository _schedules;
  final FixturePredictionRepository _fixturePredictions;
  final IdGenerator _ids;
  final List<ProviderLeagueRule> _rules;
  final String _source;

  /// Matches kicking off sooner than this are not added.
  final Duration minimumLead;

  static final RegExp _monthlyLabel = RegExp(r'^\d{2}/\d{4}$');

  /// Runs every rule over [riyadhDays] at [now]; writes only when [apply].
  Future<Result<ProviderSyncReport>> call({
    required DateTime now,
    required List<DateTime> riyadhDays,
    required bool apply,
  }) async {
    final nowUtc = now.toUtc();

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
        .where((season) => _monthlyLabel.hasMatch(season.label))
        .toList(growable: false);

    final notes = <String>[];
    final nextOrder = <String, int>{};
    var requests = 0;
    var applied = 0;
    var known = 0;
    var skipped = 0;

    for (final rule in _rules) {
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

      for (final day in riyadhDays) {
        requests++;
        final fetched = await _provider.matchesOn(
          leagueExternalId: rule.externalLeagueId,
          riyadhDay: day,
        );
        if (fetched is Err<List<ProviderMatch>>) {
          notes.add(
            'fetch ${rule.externalLeagueId} ${isoDay(day)} failed: '
            '${fetched.error.code}',
          );
          if (fetched.error.code == providerQuotaErrorCode) {
            return Result.ok(
              ProviderSyncReport(
                requests: requests,
                applied: applied,
                alreadyKnown: known,
                skipped: skipped,
                notes: notes,
              ),
            );
          }
          continue;
        }

        final candidates = (fetched as Ok<List<ProviderMatch>>).value
            .where(
              (match) =>
                  match.status == ProviderMatchStatus.scheduled &&
                  match.kickoffAt.isAfter(nowUtc.add(minimumLead)) &&
                  rule.admits(match),
            )
            .toList(growable: false);
        if (candidates.isEmpty) {
          continue;
        }

        final teamIdsResult = await _store.canonicalIds(
          source: _source,
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
          source: _source,
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
          if (fixtureIds.containsKey(match.externalId)) {
            known++;
            continue;
          }
          final home = teamById[teamIds[match.homeTeamExternalId]];
          final away = teamById[teamIds[match.awayTeamExternalId]];
          if (home == null || away == null) {
            skipped++;
            notes.add(
              'unmapped team: ${match.homeTeamName} '
              '(${match.homeTeamExternalId}) vs ${match.awayTeamName} '
              '(${match.awayTeamExternalId})',
            );
            continue;
          }
          if (pairLeague != null &&
              (home.leagueId != pairLeague.id ||
                  away.leagueId != pairLeague.id)) {
            skipped++;
            continue;
          }
          final month = _monthContaining(months, match.kickoffAt);
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
          if (!apply) {
            applied++;
            notes.add('would add: $label');
            continue;
          }

          final added = await _add(
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

    return Result.ok(
      ProviderSyncReport(
        requests: requests,
        applied: applied,
        alreadyKnown: known,
        skipped: skipped,
        notes: notes,
      ),
    );
  }

  Future<Result<void>> _add({
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
      source: _source,
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

  static CompetitionSeason? _monthContaining(
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
}
