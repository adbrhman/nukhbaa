import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart' show FakeIdGenerator;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

// Script 190: the daily selection, through the fixtures sync that drives it.

const _pl = 'a1000000-0000-0000-0000-000000000001';
const _laLiga = 'a1000000-0000-0000-0000-000000000002';
const _roshan = 'a1000000-0000-0000-0000-000000000003';
const _competition = 'c1000000-0000-0000-0000-000000000001';
const _november = 'd1000000-0000-0000-0000-000000000011';

// Thursday 5 November 21:05 UTC is Friday 6 November 00:05 in Riyadh: the
// first run of the day before Saturday 7 November.
final _now = DateTime.utc(2026, 11, 5, 21, 5);
final _day = DateTime.utc(2026, 11, 7);
final _kickoff = DateTime.utc(2026, 11, 7, 17);

const _plName = 'الإنجليزي';
const _laLigaName = 'الإسباني';
const _roshanName = 'السعودي';

const _rules = [
  ProviderLeagueRule(
    source: 'football-data',
    externalLeagueId: 'PL',
    leagueName: _plName,
  ),
  ProviderLeagueRule(
    source: 'football-data',
    externalLeagueId: 'PD',
    leagueName: _laLigaName,
    clubs: {'rm'},
  ),
  ProviderLeagueRule(
    source: 'highlightly',
    externalLeagueId: '262041',
    leagueName: _roshanName,
    clubs: {'hil'},
  ),
];

const _leagues = [
  DailySelectionLeague(
    leagueName: _laLigaName,
    standings: StandingsRef(source: 'football-data', leagueRef: 'PD'),
  ),
  DailySelectionLeague(
    leagueName: _roshanName,
    standings: StandingsRef(source: 'highlightly', leagueRef: '262041'),
    guaranteed: true,
  ),
];

/// Club key -> (league id, provider source, table position).
const _clubs = <String, (String, String, int)>{
  'ars': (_pl, 'football-data', 0),
  'che': (_pl, 'football-data', 0),
  'rm': (_laLiga, 'football-data', 1),
  'bar': (_laLiga, 'football-data', 2),
  'atl': (_laLiga, 'football-data', 3),
  'vil': (_laLiga, 'football-data', 4),
  'get': (_laLiga, 'football-data', 15),
  'cad': (_laLiga, 'football-data', 19),
  'gir': (_laLiga, 'football-data', 20),
  'hil': (_roshan, 'highlightly', 1),
  'nas': (_roshan, 'highlightly', 2),
  'itt': (_roshan, 'highlightly', 3),
  'tah': (_roshan, 'highlightly', 6),
  'sh1': (_roshan, 'highlightly', 17),
  'sh2': (_roshan, 'highlightly', 18),
};

String _teamId(String club) =>
    'b1000000-0000-0000-0000-${(_clubs.keys.toList().indexOf(club) + 1).toString().padLeft(12, '0')}';

List<String> _fixtureIds() => [
  for (var i = 1; i <= 30; i++)
    'e1000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
];

/// Tables by provider league ref, from [_clubs].
final class _Tables implements LeagueStandingsSource {
  _Tables(this.leagueOf);

  final String Function(String leagueRef) leagueOf;
  final List<String> calls = <String>[];

  @override
  Future<Result<List<LeagueStandingRow>>> standingsOf({
    required String leagueRef,
    required int season,
  }) async {
    calls.add(leagueRef);
    final league = leagueOf(leagueRef);
    return Result.ok([
      for (final entry in _clubs.entries)
        if (entry.value.$1 == league)
          LeagueStandingRow(
            teamExternalId: entry.key,
            position: entry.value.$3,
          ),
    ]);
  }
}

final class _MemoryStandings implements LeagueStandingsStore {
  final Map<String, StoredLeagueTable> kept = {};

  @override
  Future<Result<StoredLeagueTable?>> latest({
    required String source,
    required String leagueRef,
  }) async => Result.ok(kept['$source:$leagueRef']);

  @override
  Future<Result<void>> save({
    required String source,
    required String leagueRef,
    required List<LeagueStandingRow> rows,
    required DateTime fetchedAt,
  }) async {
    kept['$source:$leagueRef'] = StoredLeagueTable(
      rows: rows,
      fetchedAt: fetchedAt,
    );
    return const Result.ok(null);
  }
}

final class _Log implements DailySelectionLog {
  final Map<String, (DailySelectionDay, List<DailySelectionCandidate>)> days =
      {};

  @override
  Future<Result<void>> record({
    required DailySelectionDay day,
    required List<DailySelectionCandidate> candidates,
    required DateTime at,
  }) async {
    days[isoDay(day.day)] = (day, candidates);
    return const Result.ok(null);
  }

  String decisionOf(String externalId) => days[isoDay(_day)]!.$2
      .firstWhere((c) => c.externalId == externalId)
      .decision;
}

final class _Alert implements DailyShortfallAlert {
  final List<(DateTime, int)> sent = <(DateTime, int)>[];

  @override
  Future<Result<void>> send({
    required DateTime day,
    required int fixtureCount,
    required int minimum,
    required DateTime? firstKickoff,
  }) async {
    sent.add((day, fixtureCount));
    return const Result.ok(null);
  }
}

ProviderMatch _match(String id, String league, String home, String away) =>
    providerMatch(
      id: id,
      league: league,
      home: home,
      away: away,
      kickoff: _kickoff,
    );

void main() {
  late FakeFootballDataProvider footballData;
  late FakeFootballDataProvider highlightly;
  late FakeProviderSyncStore store;
  late FakeFixtureScheduleRepository schedules;
  late _Log log;
  late _Alert alert;
  late Map<DateTime, (int, DateTime?)> handAdded;

  setUp(() {
    footballData = FakeFootballDataProvider();
    highlightly = FakeFootballDataProvider();
    store = FakeProviderSyncStore();
    for (final entry in _clubs.entries) {
      store.map['${entry.value.$2}|team|${entry.key}'] = _teamId(entry.key);
    }
    schedules = FakeFixtureScheduleRepository();
    log = _Log();
    alert = _Alert();
    handAdded = {};
  });

  /// The day count the rounds use: the fixtures the sync saved, and those
  /// an admin added by hand ([handAdded]: how many, first kickoff).
  Future<Result<H2hDayFixtures>> countDay(DateTime day) async {
    final saved =
        ((await schedules.findByFixtures([
                  for (final id in _fixtureIds()) FixtureRef(id),
                ]))
                as Ok<List<FixtureSchedule>>)
            .value;
    final kickoffs = <DateTime>[
      for (final s in saved)
        if (riyadhDayOf(s.kickoffAt) == day) s.kickoffAt,
      if (handAdded[day]?.$2 case final DateTime first) first,
    ]..sort();
    final count =
        (handAdded[day]?.$1 ?? 0) +
        saved.where((s) => riyadhDayOf(s.kickoffAt) == day).length;
    return Result.ok(
      H2hDayFixtures(
        day: day,
        fixtureCount: count,
        firstKickoff: kickoffs.isEmpty ? null : kickoffs.first,
      ),
    );
  }

  SyncProviderFixtures sync({
    required DailySelectionMode mode,
    required DailySelectionPolicy policy,
    List<DailySelectionLeague> leagues = _leagues,
  }) {
    final competitions = FakeCompetitionRepository()
      ..seedSeason(
        CompetitionSeason.fromStored(
          id: const SeasonId(_november),
          competitionId: const CompetitionId(_competition),
          label: '11/2026',
          startAt: DateTime.utc(2026, 11),
          endAt: DateTime.utc(2026, 12),
        ),
      );
    final tables = _Tables(
      (ref) => switch (ref) {
        'PD' => _laLiga,
        '262041' => _roshan,
        _ => _pl,
      },
    );
    return SyncProviderFixtures(
      providers: {'football-data': footballData, 'highlightly': highlightly},
      store: store,
      leagueRepository: FakeLeagueRepository(const [
        League(
          id: LeagueRef(_pl),
          name: _plName,
          shortName: null,
          logoUrl: null,
        ),
        League(
          id: LeagueRef(_laLiga),
          name: _laLigaName,
          shortName: null,
          logoUrl: null,
        ),
        League(
          id: LeagueRef(_roshan),
          name: _roshanName,
          shortName: null,
          logoUrl: null,
        ),
      ]),
      teamRepository: FakeTeamRepository([
        for (final entry in _clubs.entries)
          Team(
            id: TeamRef(_teamId(entry.key)),
            name: entry.key,
            shortName: null,
            crestUrl: null,
            leagueId: LeagueRef(entry.value.$1),
          ),
      ]),
      competitionRepository: competitions,
      fixtureScheduleRepository: schedules,
      fixturePredictionRepository: FakeFixturePredictionRepository(),
      idGenerator: FakeIdGenerator(_fixtureIds()),
      rules: _rules,
      dailySelection: DailyFixtureSelection(
        mode: mode,
        leagues: leagues,
        bigClubRefs: const <String>{},
        derbies: const <MatchDetailsDerby>[],
        policy: policy,
        tables: LeagueTables(
          sources: {'football-data': tables, 'highlightly': tables},
          store: _MemoryStandings(),
          identities: store,
        ),
        identities: store,
        dayFixtures: countDay,
        log: log,
        alert: alert,
      ),
    );
  }

  void answerTheDay() {
    footballData
      ..answer('PL', _day, [_match('pl1', 'PL', 'ars', 'che')])
      ..answer('PD', _day, [
        _match('pd1', 'PD', 'rm', 'bar'),
        _match('pd2', 'PD', 'atl', 'get'),
        _match('pd3', 'PD', 'cad', 'gir'),
      ]);
    highlightly.answer('262041', _day, [
      _match('sa1', '262041', 'hil', 'nas'),
      _match('sa2', '262041', 'sh1', 'sh2'),
    ]);
  }

  List<String> added(ProviderSyncReport report) => [
    for (final note in report.notes)
      if (note.contains(': added ')) note.split(': added ').last,
  ];

  test(
    'on: the strongest are added, a weak one is left above the minimum',
    () async {
      answerTheDay();
      final run = sync(
        mode: DailySelectionMode.on,
        policy: const DailySelectionPolicy(minimum: 3, target: 4),
      );

      final report =
          ((await run.call(now: _now, riyadhDays: [_day], apply: true))
                  as Ok<ProviderSyncReport>)
              .value;

      // The Premier League by its rule; Real Madrid's match, though its club
      // rule admits it, only by the selection.
      expect(added(report), ['hil - nas (58)', 'rm - bar (58)']);
      expect(report.applied, 3);
      expect(store.map['football-data|fixture|pl1'], isNotNull);
      expect(store.map['football-data|fixture|pd2'], isNull);
      expect(log.decisionOf('pd2'), 'أضعف من الحد');
      expect(log.decisionOf('sa1'), 'أُضيفت');
      final (day, _) = log.days[isoDay(_day)]!;
      expect((day.baseCount, day.chosen, day.finalCount), (1, 2, 3));
      expect(alert.sent, isEmpty);
    },
  );

  test('below the minimum every suitable match is taken, then the owner '
      'is told once', () async {
    answerTheDay();
    final run = sync(
      mode: DailySelectionMode.on,
      policy: const DailySelectionPolicy(minimum: 8, target: 9),
    );

    await run.call(now: _now, riyadhDays: [_day], apply: true);

    expect(log.days[isoDay(_day)]!.$1.finalCount, 6);
    expect(alert.sent, [(_day, 6)]);

    // Two hours later: the same day is not reported again.
    await run.call(
      now: _now.add(const Duration(hours: 2)),
      riyadhDays: [_day],
      apply: true,
    );
    expect(alert.sent, hasLength(1));
    expect(log.decisionOf('pd1'), 'على الجدول');
  });

  test('shadow: the club rules still add, the choice is only logged', () async {
    answerTheDay();
    final run = sync(
      mode: DailySelectionMode.shadow,
      policy: const DailySelectionPolicy(minimum: 3, target: 4),
    );

    final report =
        ((await run.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    // The rules as today: the Premier League, Real Madrid, Al Hilal.
    expect(report.applied, 3);
    expect(added(report), isEmpty);
    expect(store.map['football-data|fixture|pd2'], isNull);
    final (day, _) = log.days[isoDay(_day)]!;
    expect(day.mode, 'shadow');
    // As if the selection had chosen from the start.
    expect((day.baseCount, day.chosen, day.finalCount), (1, 2, 3));
    expect(log.decisionOf('pd1'), 'تُختار (موجودة الآن)');
    expect(log.decisionOf('pd2'), 'أضعف من الحد');
    expect(alert.sent, isEmpty);
  });

  test('a day not read for every league is not chosen', () async {
    answerTheDay();
    highlightly.answers['262041|${isoDay(_day)}'] = const Result.err(
      AppError.transient('football_data.provider_http_500', 'down'),
    );
    final run = sync(
      mode: DailySelectionMode.on,
      policy: const DailySelectionPolicy(minimum: 3, target: 4),
    );

    final report =
        ((await run.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    expect(added(report), isEmpty);
    expect(
      report.notes.any((n) => n.contains('not every league was read')),
      isTrue,
    );
    // 00:05: the 12:05 run may still read it, so nobody is told yet.
    expect(alert.sent, isEmpty);
  });

  test('a day whose first match has kicked off is left alone', () async {
    answerTheDay();
    handAdded[_day] = (1, _now.subtract(const Duration(minutes: 1)));
    final run = sync(
      mode: DailySelectionMode.on,
      policy: const DailySelectionPolicy(minimum: 3, target: 4),
    );

    final report =
        ((await run.call(now: _now, riyadhDays: [_day], apply: true))
                as Ok<ProviderSyncReport>)
            .value;

    expect(added(report), isEmpty);
    expect(report.notes, contains('selection 2026-11-07: the day has begun'));
  });

  test(
    'a league with matches on the day already gives way to another',
    () async {
      footballData.answer('PD', _day, [
        _match('pd1', 'PD', 'rm', 'bar'),
        _match('pd4', 'PD', 'atl', 'vil'),
      ]);
      highlightly.answer('262041', _day, [
        _match('sa3', '262041', 'nas', 'tah'),
      ]);
      final run = sync(
        mode: DailySelectionMode.on,
        policy: const DailySelectionPolicy(minimum: 1, target: 3),
        leagues: const [
          DailySelectionLeague(
            leagueName: _laLigaName,
            standings: StandingsRef(source: 'football-data', leagueRef: 'PD'),
          ),
          DailySelectionLeague(
            leagueName: _roshanName,
            standings: StandingsRef(source: 'highlightly', leagueRef: '262041'),
          ),
        ],
      );

      final report =
          ((await run.call(now: _now, riyadhDays: [_day], apply: true))
                  as Ok<ProviderSyncReport>)
              .value;

      // 58, then the Saudi 48 before La Liga's 52 less 8.
      expect(added(report), [
        'rm - bar (58)',
        'nas - tah (48)',
        'atl - vil (52)',
      ]);
    },
  );

  test('a busy day may hold up to the busy target', () async {
    answerTheDay();
    final run = sync(
      mode: DailySelectionMode.on,
      policy: const DailySelectionPolicy(
        minimum: 1,
        target: 2,
        busyTarget: 4,
        minimumScore: 20,
        busyLeagues: {_laLigaName, _roshanName},
      ),
    );

    await run.call(now: _now, riyadhDays: [_day], apply: true);

    final (day, _) = log.days[isoDay(_day)]!;
    expect(day.busy, isTrue);
    expect(day.target, 4);
    expect(day.finalCount, 4);
  });
}
