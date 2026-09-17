import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _pl = 'a1000000-0000-0000-0000-000000000001';

final class _Board implements LiveScoreBoard {
  final Map<String, LiveScore> scores = {};

  @override
  void put(Map<String, LiveScore> s) => scores.addAll(s);

  @override
  void remove(Iterable<String> ids) => ids.forEach(scores.remove);

  @override
  Map<String, LiveScore> read(Iterable<String> ids) => {
    for (final id in ids)
      if (scores[id] != null) id: scores[id]!,
  };
}

void main() {
  final kickoff = DateTime.utc(2026, 9, 19, 14);
  final now = DateTime.utc(2026, 9, 19, 15);

  late FakeFootballDataProvider provider;
  late FakeProviderSyncStore store;
  late _Board board;

  RefreshLiveScores build(Set<String> liveSources) => RefreshLiveScores(
    providers: {'football-data': provider},
    store: store,
    leagueRepository: FakeLeagueRepository(const [
      League(
        id: LeagueRef(_pl),
        name: 'الإنجليزي',
        shortName: null,
        logoUrl: null,
      ),
    ]),
    rules: const [
      ProviderLeagueRule(
        source: 'football-data',
        externalLeagueId: 'PL',
        leagueName: 'الإنجليزي',
      ),
    ],
    board: board,
    liveSources: liveSources,
  );

  setUp(() {
    provider = FakeFootballDataProvider();
    board = _Board()
      ..scores['gone'] = LiveScore(
        homeGoals: 0,
        awayGoals: 0,
        finished: false,
        updatedAt: now,
      );
    store = FakeProviderSyncStore()
      ..pending = [
        PendingProviderFixture(
          fixtureId: 'f-live',
          externalId: 'm1',
          kickoffAt: kickoff,
          leagueId: _pl,
        ),
        PendingProviderFixture(
          fixtureId: 'gone',
          externalId: 'm2',
          kickoffAt: kickoff,
          leagueId: _pl,
        ),
      ];
    provider.answer('PL', riyadhDayOf(kickoff), [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'a',
        away: 'b',
        kickoff: kickoff,
        status: ProviderMatchStatus.live,
      ),
      providerMatch(
        id: 'm2',
        league: 'PL',
        home: 'c',
        away: 'd',
        kickoff: kickoff,
        status: ProviderMatchStatus.postponed,
      ),
    ]);
  });

  test('a live match without a running score is not shown; a postponed one '
      'is cleared', () async {
    final result = await build({'football-data'}).call(now: now);

    expect(result.isOk, isTrue);
    expect(board.scores.containsKey('f-live'), isFalse);
    expect(board.scores.containsKey('gone'), isFalse);
    expect(provider.calls, hasLength(1));
  });

  test('a running score is shown with its minute', () async {
    provider.answer('PL', riyadhDayOf(kickoff), [
      providerMatch(
        id: 'm1',
        league: 'PL',
        home: 'a',
        away: 'b',
        kickoff: kickoff,
        status: ProviderMatchStatus.live,
        currentHomeGoals: 2,
        currentAwayGoals: 1,
        minute: 58,
      ),
    ]);

    final result = await build({'football-data'}).call(now: now);

    expect(result.isOk, isTrue);
    final score = board.scores['f-live']!;
    expect((score.homeGoals, score.awayGoals, score.minute), (2, 1, 58));
    expect(score.finished, isFalse);
  });

  test(
    'a finished match shows its final score until a result is recorded',
    () async {
      provider.answer('PL', riyadhDayOf(kickoff), [
        providerMatch(
          id: 'm1',
          league: 'PL',
          home: 'a',
          away: 'b',
          kickoff: kickoff,
          status: ProviderMatchStatus.finished,
          homeGoals: 3,
          awayGoals: 0,
        ),
      ]);

      await build({'football-data'}).call(now: now);

      expect(board.scores['f-live']!.finished, isTrue);
      expect(board.scores['f-live']!.homeGoals, 3);
    },
  );

  test('a provider outside liveSources is never asked', () async {
    await build(const {}).call(now: now);
    expect(provider.calls, isEmpty);
  });
}
