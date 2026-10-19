import 'package:application/application.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _paris = 'f1000000-0000-0000-0000-000000000018';
const _lorient = 'f1000000-0000-0000-0000-000000000019';
const _nassr = 'f1000000-0000-0000-0000-000000000020';
const _elsewhere = 'f1000000-0000-0000-0000-000000000021';

final _kickoff = DateTime.utc(2026, 10, 18, 15, 15);
final _now = DateTime.utc(2026, 10, 18, 19);
final _day = riyadhDayOf(_kickoff);

final class _Store implements MatchDetailsStore {
  List<PendingMatchDetails> fixtures = <PendingMatchDetails>[];
  final Map<String, MatchDetails> saved = <String, MatchDetails>{};

  @override
  Future<Result<List<PendingMatchDetails>>> pending({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  }) async => Result.ok(<PendingMatchDetails>[
    for (final f in fixtures)
      if (!saved.containsKey(f.fixtureId) &&
          !f.kickoffAt.isBefore(kickedOffFrom) &&
          f.kickoffAt.isBefore(kickedOffBefore))
        f,
  ]);

  @override
  Future<Result<void>> save(MatchDetails details) async {
    saved[details.fixtureId] = details;
    return const Result.ok(null);
  }

  @override
  Future<Result<MatchDetails?>> find(String fixtureId) async =>
      Result.ok(saved[fixtureId]);
}

final class _Source implements MatchDetailsSource {
  final List<String> asked = <String>[];
  bool over = true;
  bool quota = false;

  @override
  String get source => 'highlightly';

  @override
  Future<Result<MatchDetails?>> details({
    required String externalMatchId,
    required String fixtureId,
  }) async {
    asked.add(externalMatchId);
    if (quota) {
      return const Result.err(
        AppError.transient(providerQuotaErrorCode, 'reserve'),
      );
    }
    if (!over) {
      return const Result.ok(null);
    }
    return Result.ok(
      MatchDetails(
        fixtureId: fixtureId,
        found: true,
        source: source,
        externalMatchId: externalMatchId,
        fetchedAt: _now,
        events: const <MatchEvent>[
          MatchEvent(
            minute: '51',
            kind: MatchEventKind.varGoalCancelled,
            home: false,
          ),
        ],
      ),
    );
  }
}

PendingMatchDetails _pending(
  String id, {
  String league = 'الدوري الفرنسي',
  DateTime? kickoff,
  int home = 4,
  int away = 3,
  String? externalId,
}) => PendingMatchDetails(
  fixtureId: id,
  kickoffAt: kickoff ?? _kickoff,
  leagueName: league,
  homeGoals: home,
  awayGoals: away,
  externalMatchId: externalId,
);

void main() {
  late _Store store;
  late _Source source;
  late FakeFootballDataProvider lister;

  SyncMatchDetails sync() => SyncMatchDetails(
    store: store,
    source: source,
    lister: lister,
    leagueIds: const <String, String>{
      'الدوري الفرنسي': '52695',
      'دوري روشن السعودي': '262041',
    },
  );

  void ligue1(List<ProviderMatch> matches) =>
      lister.answer('52695', _day, matches);

  ProviderMatch match(
    String id, {
    DateTime? kickoff,
    int? home,
    int? away,
    ProviderMatchStatus status = ProviderMatchStatus.finished,
  }) => providerMatch(
    id: id,
    league: '52695',
    home: 'h$id',
    away: 'a$id',
    kickoff: kickoff ?? _kickoff,
    status: status,
    homeGoals: home,
    awayGoals: away,
  );

  setUp(() {
    store = _Store();
    source = _Source();
    lister = FakeFootballDataProvider();
  });

  test('a match is found by its kickoff in its league that day, and its '
      'story stored once', () async {
    store.fixtures = <PendingMatchDetails>[_pending(_paris)];
    ligue1(<ProviderMatch>[
      match('1321424223', home: 4, away: 3),
      match('1321422521', kickoff: _kickoff.add(const Duration(hours: 2))),
    ]);

    final report =
        ((await sync().call(now: _now)) as Ok<MatchDetailsReport>).value;

    expect(lister.calls, <String>['52695|${isoDay(_day)}']);
    expect(source.asked, <String>['1321424223']);
    expect(store.saved[_paris]!.found, isTrue);
    expect((report.requests, report.saved, report.notFound), (2, 1, 0));

    await sync().call(now: _now.add(const Duration(minutes: 30)));
    expect(source.asked, hasLength(1));
  });

  test('a single match at that kickoff is taken even when the feed got its '
      'score wrong, the case of a goal ruled out by VAR', () async {
    store.fixtures = <PendingMatchDetails>[_pending(_paris)];
    ligue1(<ProviderMatch>[match('1321424223', home: 4, away: 4)]);

    await sync().call(now: _now);

    expect(source.asked, <String>['1321424223']);
  });

  test('two matches kicking off together are told apart by the score, one '
      'list call for both', () async {
    store.fixtures = <PendingMatchDetails>[
      _pending(_paris),
      _pending(_lorient, home: 1, away: 0),
    ];
    ligue1(<ProviderMatch>[
      match('1321424223', home: 4, away: 3),
      match('1321422521', home: 1, away: 0),
    ]);

    await sync().call(now: _now);

    expect(lister.calls, hasLength(1));
    expect(source.asked, <String>['1321424223', '1321422521']);
    expect(store.saved.keys, containsAll(<String>[_paris, _lorient]));
  });

  test('a fixture the provider has no match for is stored as not found and '
      'never asked about again', () async {
    store.fixtures = <PendingMatchDetails>[_pending(_paris)];
    ligue1(<ProviderMatch>[
      match('9', kickoff: _kickoff.add(const Duration(hours: 1))),
    ]);

    final report =
        ((await sync().call(now: _now)) as Ok<MatchDetailsReport>).value;
    await sync().call(now: _now.add(const Duration(hours: 1)));

    expect(store.saved[_paris]!.found, isFalse);
    expect(report.notFound, 1);
    expect(source.asked, isEmpty);
    expect(lister.calls, hasLength(1));
  });

  test('a match not over yet is asked about again on a later run', () async {
    store.fixtures = <PendingMatchDetails>[_pending(_paris)];
    ligue1(<ProviderMatch>[
      match('1321424223', status: ProviderMatchStatus.live),
    ]);

    await sync().call(now: _now);
    expect(store.saved, isEmpty);
    expect(source.asked, isEmpty);

    ligue1(<ProviderMatch>[match('1321424223', home: 4, away: 3)]);
    await sync().call(now: _now.add(const Duration(minutes: 30)));
    expect(store.saved[_paris]!.found, isTrue);
  });

  test("a fixture from the provider itself is read by its own id, with no "
      'list call', () async {
    store.fixtures = <PendingMatchDetails>[
      _pending(_nassr, league: 'دوري روشن السعودي', externalId: '777'),
    ];

    await sync().call(now: _now);

    expect(lister.calls, isEmpty);
    expect(source.asked, <String>['777']);
  });

  test('a league with no provider id is never asked about', () async {
    store.fixtures = <PendingMatchDetails>[
      _pending(_elsewhere, league: 'كأس أمم إفريقيا'),
    ];

    final report =
        ((await sync().call(now: _now)) as Ok<MatchDetailsReport>).value;

    expect(report.requests, 0);
    expect(store.saved, isEmpty);
  });

  test('nothing is asked before the match can be over', () async {
    store.fixtures = <PendingMatchDetails>[_pending(_paris)];

    await sync().call(now: _kickoff.add(const Duration(hours: 1)));

    expect(lister.calls, isEmpty);
  });

  test('the reserve of the daily quota stops the run', () async {
    store.fixtures = <PendingMatchDetails>[
      _pending(_nassr, league: 'دوري روشن السعودي', externalId: '777'),
      _pending(_paris, externalId: '1321424223'),
    ];
    source.quota = true;

    final report =
        ((await sync().call(now: _now)) as Ok<MatchDetailsReport>).value;

    expect(source.asked, <String>['777']);
    expect(store.saved, isEmpty);
    expect(report.notes.single, contains(providerQuotaErrorCode));
  });

  test(
    'a run says how many fixtures wait, and why one was passed over',
    () async {
      store.fixtures = <PendingMatchDetails>[
        _pending(_elsewhere, league: 'كأس أمم إفريقيا'),
        _pending(_paris),
      ];
      ligue1(<ProviderMatch>[
        match('1321424223', status: ProviderMatchStatus.live),
      ]);

      final report =
          ((await sync().call(now: _now)) as Ok<MatchDetailsReport>).value;

      expect(report.pending, 2);
      expect(report.notes, hasLength(2));
      expect(report.notes.first, contains('كأس أمم إفريقيا'));
      expect(report.notes.last, contains('1321424223'));
    },
  );

  test('the half-time score comes from the goals up to 45+', () {
    const events = <MatchEvent>[
      MatchEvent(minute: '14', kind: MatchEventKind.goal, home: true),
      MatchEvent(minute: '29', kind: MatchEventKind.penaltyGoal, home: false),
      MatchEvent(minute: '45+4', kind: MatchEventKind.goal, home: true),
      MatchEvent(minute: '74', kind: MatchEventKind.penaltyGoal, home: false),
      MatchEvent(minute: '23', kind: MatchEventKind.yellowCard, home: false),
    ];
    expect(MatchDetails.halfTimeFromEvents(events), (2, 1));
  });
}
