import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Provider answering from a script keyed by `league|yyyy-mm-dd`.
final class FakeFootballDataProvider implements FootballDataProvider {
  final Map<String, Result<List<ProviderMatch>>> answers = {};
  final List<String> calls = <String>[];

  void answer(String league, DateTime day, List<ProviderMatch> matches) =>
      answers['$league|${isoDay(day)}'] = Result.ok(matches);

  @override
  Future<Result<List<ProviderMatch>>> matchesOn({
    required String leagueExternalId,
    required DateTime riyadhDay,
  }) async {
    final key = '$leagueExternalId|${isoDay(riyadhDay)}';
    calls.add(key);
    return answers[key] ?? const Result.ok(<ProviderMatch>[]);
  }
}

/// In-memory identity map plus a scripted pending list.
final class FakeProviderSyncStore implements ProviderSyncStore {
  final Map<String, String> map = {};
  List<PendingProviderFixture> pending = const <PendingProviderFixture>[];

  static String _key(String source, String table, String externalId) =>
      '$source|$table|$externalId';

  void seed(String table, String externalId, String canonicalId) =>
      map[_key('highlightly', table, externalId)] = canonicalId;

  @override
  Future<Result<Map<String, String>>> canonicalIds({
    required String source,
    required String table,
    required List<String> externalIds,
  }) async => Result.ok({
    for (final id in externalIds)
      if (map[_key(source, table, id)] != null)
        id: map[_key(source, table, id)]!,
  });

  @override
  Future<Result<void>> link({
    required String source,
    required String table,
    required String externalId,
    required String canonicalId,
  }) async {
    map.putIfAbsent(_key(source, table, externalId), () => canonicalId);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<PendingProviderFixture>>> fixturesAwaitingResult({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  }) async => Result.ok([
    for (final p in pending)
      if (!p.kickoffAt.isBefore(kickedOffFrom) &&
          p.kickoffAt.isBefore(kickedOffBefore))
        p,
  ]);
}

final class FakeLeagueRepository implements LeagueRepository {
  FakeLeagueRepository(this.leagues);
  final List<League> leagues;

  @override
  Future<Result<List<League>>> listAll() async => Result.ok(leagues);
}

final class FakeTeamRepository implements TeamRepository {
  FakeTeamRepository(this.teams);
  final List<Team> teams;

  @override
  Future<Result<List<Team>>> listAll() async => Result.ok(teams);
}

ProviderMatch providerMatch({
  required String id,
  required String league,
  required String home,
  required String away,
  required DateTime kickoff,
  ProviderMatchStatus status = ProviderMatchStatus.scheduled,
  int? homeGoals,
  int? awayGoals,
}) => ProviderMatch(
  externalId: id,
  leagueExternalId: league,
  homeTeamExternalId: home,
  awayTeamExternalId: away,
  homeTeamName: 'home-$home',
  awayTeamName: 'away-$away',
  kickoffAt: kickoff,
  status: status,
  homeGoals: homeGoals,
  awayGoals: awayGoals,
);
