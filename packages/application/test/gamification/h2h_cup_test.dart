/// The Elite Cup through the real job (NK185, migration 0190): the
/// qualifiers once the 19 rounds are judged, the four cup days one after the
/// other on the next qualifying days with paths 2 and 3 side by side (NK276,
/// migration 0212), the decisions, the titles, a stage carried to another
/// day, and nothing before the league is finished.
library;

import 'dart:math';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

H2hLeagueId _group(int g) =>
    H2hLeagueId('11111111-1111-4111-8111-00000000000$g');

H2hRoundId _rid(int n) =>
    H2hRoundId('22222222-2222-4222-8222-${n.toString().padLeft(12, '0')}');

/// Player s (slot 0..3) of elite group g (1..4).
UserId _p(int g, int s) => userNo(g * 10 + s);

/// Kickoff of a cup day: 15:00 UTC (18:00 Riyadh).
DateTime _kick(int day) => DateTime.utc(2026, 11, day, 15);

final class _Cups implements H2hCupStore {
  final List<H2hCupEntry> entries = <H2hCupEntry>[];
  final List<H2hCupStage> stages = <H2hCupStage>[];
  final List<H2hCupTitle> titles = <H2hCupTitle>[];
  final Map<String, H2hCupStageFigures> figures =
      <String, H2hCupStageFigures>{};
  final List<int> roundDays = <int>[];

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async => Result.ok(
    H2hCupState(
      entries: List.of(entries),
      // As stagesSql reads them: day, then path, then attempt.
      stages: List.of(stages)
        ..sort((a, b) {
          final byDay = a.day.compareTo(b.day);
          if (byDay != 0) return byDay;
          final byPlace = a.step.place.compareTo(b.step.place);
          if (byPlace != 0) return byPlace;
          return a.attempt.compareTo(b.attempt);
        }),
      titles: List.of(titles),
    ),
  );

  @override
  Future<Result<void>> enter(
    DateTime monthStart,
    List<H2hCupEntry> list,
  ) async {
    for (final e in list) {
      if (!entries.any((x) => x.userId == e.userId)) {
        entries.add(e);
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> schedule({
    required H2hCupStageId id,
    required DateTime monthStart,
    required H2hCupStep step,
    required int attempt,
    required DateTime day,
    required int fixtureCount,
    required List<H2hCupPair> pairs,
  }) async {
    // The database's backstop (0190, 0212): a later day than every stage,
    // or the same day for the other path of the same cup day; never an
    // earlier cup day after a later one.
    if (stages.any(
      (s) =>
          s.day.isAfter(day) ||
          s.step.cupDay > step.cupDay ||
          (s.day == day &&
              (s.step.cupDay != step.cupDay || s.step.place == step.place)),
    )) {
      return const Result.err(
        AppError.invariant('h2h.cup_refused', 'out of order'),
      );
    }
    stages.add(
      H2hCupStage(
        id: id,
        monthStart: monthStart,
        step: step,
        attempt: attempt,
        day: day,
        fixtureCount: fixtureCount,
        lockedAt: null,
        pairs: pairs,
        results: const [],
      ),
    );
    return const Result.ok(null);
  }

  H2hCupStage _replace(
    H2hCupStage s, {
    DateTime? lockedAt,
    List<H2hCupResult>? results,
  }) => H2hCupStage(
    id: s.id,
    monthStart: s.monthStart,
    step: s.step,
    attempt: s.attempt,
    day: s.day,
    fixtureCount: s.fixtureCount,
    lockedAt: lockedAt ?? s.lockedAt,
    pairs: s.pairs,
    results: results ?? s.results,
  );

  @override
  Future<Result<int>> lock({
    required H2hCupStageId stageId,
    required DateTime day,
  }) async {
    final i = stages.indexWhere((s) => s.id == stageId);
    stages[i] = _replace(stages[i], lockedAt: DateTime.utc(2026, 11, 1));
    return const Result.ok(8);
  }

  @override
  Future<Result<H2hCupStageFigures>> figuresOf(H2hCupStageId stageId) async =>
      Result.ok(
        figures[stageId.value] ??
            const H2hCupStageFigures(fixtures: 8, settled: 3, sides: {}),
      );

  @override
  Future<Result<void>> decide({
    required H2hCupStageId stageId,
    required List<H2hCupResult> results,
  }) async {
    final i = stages.indexWhere((s) => s.id == stageId);
    if (stages[i].results.isEmpty) {
      stages[i] = _replace(stages[i], results: results);
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> crown({
    required DateTime monthStart,
    required int place,
    required UserId? champion,
    required UserId? runnerUp,
    required String how,
  }) async {
    if (!titles.any((t) => t.place == place)) {
      titles.add(
        H2hCupTitle(
          place: place,
          champion: champion,
          runnerUp: runnerUp,
          how: how,
        ),
      );
    }
    return const Result.ok(null);
  }

  /// Settles [stage] with [points] per player (absent when missing).
  void settle(H2hCupStage stage, Map<UserId, int> points) {
    figures[stage.id.value] = H2hCupStageFigures(
      fixtures: 8,
      settled: 8,
      sides: {
        for (final e in points.entries)
          e.key: H2hCupSide(points: e.value, exact: 0, predicted: 8),
      },
    );
  }
}

final class _Controls implements H2hControlStore {
  bool autoApprove = true;

  @override
  Future<Result<H2hSettings>> settings() async => Result.ok(
    H2hSettings(autoApprove: autoApprove, leadHours: 24, minActiveDays: 5),
  );

  @override
  Future<Result<Set<DateTime>>> excludedDays({
    required DateTime from,
    required DateTime through,
  }) async => const Result.ok(<DateTime>{});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// November drawn in four elite groups of four; [rounds] rounds approved,
/// locked and judged; in every group slot 0 is first, slot 1 second, slot 2
/// third and slot 3 fourth.
final class _World {
  _World({int rounds = 19, int judged = 19, bool pilot = false}) {
    leagues.months[_november] = H2hMonthInfo(
      monthStart: _november,
      isPilot: pilot,
      seatedCount: 16,
    );
    leagues.drawn[_november] = [
      for (var g = 1; g <= 4; g++)
        H2hDrawnGroup(
          leagueId: _group(g),
          group: H2hDrawGroup(
            division: H2hDivision.first,
            groupIndex: g - 1,
            seats: [
              for (var s = 0; s < 4; s++)
                H2hDrawSeat(userId: _p(g, s), slot: s),
            ],
          ),
        ),
    ];
    for (var n = 1; n <= rounds; n++) {
      roundStore.addRound(
        H2hRound(
          id: _rid(n),
          monthStart: _november,
          number: n,
          day: DateTime.utc(2026, 11, n),
          fixtureCount: 8,
          approvedBy: null,
          lockedAt: DateTime.utc(2026, 11, n, 12),
        ),
      );
    }
    for (var g = 1; g <= 4; g++) {
      sheets.sheets[_group(g)] = H2hGroupSheet(
        members: [
          for (var s = 0; s < 4; s++)
            H2hMember(userId: _p(g, s), slot: s, joinedAt: _november),
        ],
        scores: [
          for (var n = 1; n <= rounds; n++)
            for (var s = 0; s < 4; s++)
              H2hRoundScore(
                userId: _p(g, s),
                round: n,
                points: 10 - 2 * s,
                exactCount: s == 0 ? 1 : 0,
                predictedCount: 8,
              ),
        ],
        settledRounds: {for (var n = 1; n <= judged; n++) n},
        voidRounds: const {},
      );
    }
    for (var d = 20; d <= 30; d++) {
      roundStore.dayOf(DateTime.utc(2026, 11, d), 8, _kick(d));
    }
  }

  final leagues = FakeH2hLeagueStore();
  final roundStore = FakeH2hRoundStore();
  final sheets = FakeH2hSheetReader();
  final cups = _Cups();
  final controls = _Controls();
  final ids = SequenceIds();

  RunH2hCup get job => RunH2hCup(
    cups: cups,
    rounds: roundStore,
    leagues: leagues,
    sheets: sheets,
    idGenerator: ids,
    controls: controls,
    random: Random(3),
  );

  Future<H2hCupRun> run(DateTime now) async {
    final result = await job(now: now);
    expect(result, isA<Ok<H2hCupRun>>(), reason: '$result');
    return (result as Ok<H2hCupRun>).value;
  }
}

/// The stages of November [day], path 2 first.
List<H2hCupStage> _onDay(_World w, int day) => [
  for (final s in w.cups.stages)
    if (s.day == DateTime.utc(2026, 11, day)) s,
]..sort((a, b) => a.step.place.compareTo(b.step.place));

/// Every pair of [stage] won by its home side.
Map<UserId, int> _homeWins(H2hCupStage stage) => {
  for (final p in stage.pairs) ...{p.home: 9, p.away: 3},
};

/// A world whose path 1 is played and crowned on the 20th and 21st: paths
/// 2 and 3 drawn for the 22nd.
Future<_World> _throughPath1() async {
  final w = _World();
  await w.run(DateTime.utc(2026, 11, 19, 21, 30));
  await w.run(DateTime.utc(2026, 11, 20, 15, 30));
  w.cups.settle(w.cups.stages.single, _homeWins(w.cups.stages.single));
  await w.run(DateTime.utc(2026, 11, 20, 21));
  await w.run(DateTime.utc(2026, 11, 21, 15, 30));
  w.cups.settle(w.cups.stages.last, _homeWins(w.cups.stages.last));
  await w.run(DateTime.utc(2026, 11, 21, 21));
  return w;
}

void main() {
  /// The evening of round 19: Riyadh's November 20 has begun.
  final night19 = DateTime.utc(2026, 11, 19, 21, 30);

  test('once the 19 rounds are judged: twelve qualifiers and path 1 semi-'
      'finals drawn on the next qualifying day', () async {
    final w = _World();

    final run = await w.run(night19);

    expect(run.entered, 12);
    expect(run.scheduled, 1);
    for (var g = 1; g <= 4; g++) {
      for (var s = 0; s < 3; s++) {
        final e = w.cups.entries.singleWhere((e) => e.userId == _p(g, s));
        expect(e.place, s + 1);
        expect(e.groupNumber, g);
      }
      expect(w.cups.entries.any((e) => e.userId == _p(g, 3)), isFalse);
    }
    final semi = w.cups.stages.single;
    expect(semi.step, const H2hCupStep(1, H2hCupRound.semi));
    expect(semi.day, DateTime.utc(2026, 11, 20));
    expect(semi.pairs, hasLength(2));
    expect(
      {
        for (final p in semi.pairs) ...[p.home, p.away],
      },
      {_p(1, 0), _p(2, 0), _p(3, 0), _p(4, 0)},
    );
  });

  test('nothing before the 19th round is judged, nor with 18 rounds', () async {
    final notJudged = _World(judged: 18);
    final short = _World(rounds: 18, judged: 18);

    expect((await notJudged.run(night19)).entered, 0);
    expect(notJudged.cups.stages, isEmpty);
    expect((await short.run(night19)).entered, 0);
  });

  test('a pilot month has no cup', () async {
    final w = _World(pilot: true);

    expect((await w.run(night19)).entered, 0);
  });

  test(
    'with automatic approval off the qualifiers are stored, no stage is',
    () async {
      final w = _World()..controls.autoApprove = false;

      final run = await w.run(night19);

      expect(run.entered, 12);
      expect(w.cups.stages, isEmpty);
    },
  );

  test('the whole of path 1: semi-finals, then the final the next day, then '
      'the title and paths 2 and 3 drawn together', () async {
    final w = _World();
    await w.run(night19);
    final semi = w.cups.stages.single;

    // Before the first kickoff nothing moves; after it the stage is frozen.
    await w.run(DateTime.utc(2026, 11, 20, 14));
    expect(w.cups.stages.single.locked, isFalse);
    await w.run(DateTime.utc(2026, 11, 20, 15, 30));
    expect(w.cups.stages.single.locked, isTrue);
    expect(w.cups.stages, hasLength(1), reason: 'the final waits');

    // Settled: the home side of pair 1 and the away side of pair 2 win.
    final p1 = semi.pairs[0];
    final p2 = semi.pairs[1];
    w.cups.settle(w.cups.stages.single, {
      p1.home: 12,
      p1.away: 9,
      p2.home: 7,
      p2.away: 7,
    });
    await w.run(DateTime.utc(2026, 11, 20, 21));

    final decided = w.cups.stages.first;
    expect(decided.results, hasLength(2));
    expect(decided.results[0].winner, p1.home);
    expect(decided.results[0].outcome, 'points');
    // Level on points and exact: the better league month (all equal here
    // but the group number).
    expect(decided.results[1].outcome, 'league');
    final finale = w.cups.stages.last;
    expect(finale.step, const H2hCupStep(1, H2hCupRound.finale));
    expect(finale.day, DateTime.utc(2026, 11, 21));
    expect(finale.pairs.single.home, p1.home);
    expect(finale.pairs.single.away, decided.results[1].winner);

    await w.run(DateTime.utc(2026, 11, 21, 15, 30));
    w.cups.settle(w.cups.stages.last, {finale.pairs.single.away: 3});
    await w.run(DateTime.utc(2026, 11, 21, 21));

    final title = w.cups.titles.single;
    expect(title.place, 1);
    expect(title.champion, finale.pairs.single.away);
    expect(title.runnerUp, finale.pairs.single.home);
    expect(title.how, 'final');
    // NK276: the second and the third places, each among themselves, on
    // the same day.
    final path2 = w.cups.stages.singleWhere(
      (s) => s.step == const H2hCupStep(2, H2hCupRound.semi),
    );
    final path3 = w.cups.stages.singleWhere(
      (s) => s.step == const H2hCupStep(3, H2hCupRound.semi),
    );
    expect(path2.day, DateTime.utc(2026, 11, 22));
    expect(path3.day, DateTime.utc(2026, 11, 22));
    expect(
      {
        for (final p in path2.pairs) ...[p.home, p.away],
      },
      {_p(1, 1), _p(2, 1), _p(3, 1), _p(4, 1)},
    );
    expect(
      {
        for (final p in path3.pairs) ...[p.home, p.away],
      },
      {_p(1, 2), _p(2, 2), _p(3, 2), _p(4, 2)},
    );
  });

  test(
    'a stage whose day leaves nothing to play is carried, same pairs',
    () async {
      final w = _World();
      await w.run(night19);
      await w.run(DateTime.utc(2026, 11, 20, 15, 30));
      final semi = w.cups.stages.single;
      w.cups.figures[semi.id.value] = const H2hCupStageFigures(
        fixtures: 0,
        settled: 0,
        sides: {},
      );

      await w.run(DateTime.utc(2026, 11, 20, 21));

      expect(w.cups.stages, hasLength(2));
      final carried = w.cups.stages.last;
      expect(carried.step, semi.step);
      expect(carried.attempt, 2);
      expect(carried.day, DateTime.utc(2026, 11, 21));
      expect(
        [for (final p in carried.pairs) (p.home, p.away)],
        [for (final p in semi.pairs) (p.home, p.away)],
      );
    },
  );

  test('a semi-final both sides missed sends the other winner to the title '
      'without a final', () async {
    final w = _World();
    await w.run(night19);
    await w.run(DateTime.utc(2026, 11, 20, 15, 30));
    final semi = w.cups.stages.single;
    final p2 = semi.pairs[1];
    // Pair 1 predicted nothing; pair 2's home side won.
    w.cups.settle(semi, {p2.home: 5, p2.away: 2});

    await w.run(DateTime.utc(2026, 11, 20, 21));

    final decided = w.cups.stages.first;
    expect(decided.results[0].winner, isNull);
    expect(decided.results[0].outcome, 'both_absent');
    final title = w.cups.titles.single;
    expect(title.champion, p2.home);
    expect(title.how, 'walkover');
    // Path 1 needs no final: paths 2 and 3 are drawn next, the day after.
    expect(
      [
        for (final s in w.cups.stages.skip(1))
          '${s.step.place}${s.step.round.wire}@${s.day.day}',
      ],
      ['2semi@21', '3semi@21'],
    );
  });

  // NK276: the cup in four days (owner, 2026-11-14).
  test('the cup in four days: path 1 on days 20 and 21, paths 2 and 3 '
      'together on days 22 and 23, each its own cup', () async {
    final w = await _throughPath1();
    expect(w.cups.titles.single.place, 1);

    // Day 22: both semi-finals frozen at the same kickoff.
    await w.run(DateTime.utc(2026, 11, 22, 15, 30));
    final semis = _onDay(w, 22);
    expect(semis, hasLength(2));
    expect(semis.every((s) => s.locked), isTrue);

    // Path 2's semi-finals settled, path 3's not yet: no final may start.
    w.cups.settle(semis[0], _homeWins(semis[0]));
    await w.run(DateTime.utc(2026, 11, 22, 21));
    expect(w.cups.stages, hasLength(4), reason: 'the finals wait for both');

    w.cups.settle(semis[1], _homeWins(semis[1]));
    final day22 = await w.run(DateTime.utc(2026, 11, 22, 21, 30));
    expect(day22.scheduled, 2);
    final finals = _onDay(w, 23);
    expect(
      [for (final s in finals) '${s.step.place}${s.step.round.wire}'],
      ['2final', '3final'],
    );
    for (final f in finals) {
      final semi = semis.singleWhere((s) => s.step.place == f.step.place);
      expect(
        {f.pairs.single.home, f.pairs.single.away},
        {for (final p in semi.pairs) p.home},
        reason: 'a final is played by its own path\'s winners',
      );
    }

    // Day 23: both finals, then the cup's second and third are crowned.
    await w.run(DateTime.utc(2026, 11, 23, 15, 30));
    for (final f in _onDay(w, 23)) {
      w.cups.settle(f, {f.pairs.single.away: 4, f.pairs.single.home: 2});
    }
    final day23 = await w.run(DateTime.utc(2026, 11, 23, 21));

    expect(day23.crowned, 2);
    expect([for (final t in w.cups.titles) t.place], [1, 2, 3]);
    for (final f in finals) {
      final title = w.cups.titles.singleWhere((t) => t.place == f.step.place);
      expect(title.champion, f.pairs.single.away);
      expect(title.runnerUp, f.pairs.single.home);
      expect(title.how, 'final');
    }
    expect(w.cups.stages, hasLength(6));
    expect((await w.run(DateTime.utc(2026, 11, 24, 21))).scheduled, 0);
  });

  test('a cup day with nothing to play carries both paths to the same next '
      'day, same pairs', () async {
    final w = await _throughPath1();
    await w.run(DateTime.utc(2026, 11, 22, 15, 30));
    final semis = _onDay(w, 22);
    for (final s in semis) {
      w.cups.figures[s.id.value] = const H2hCupStageFigures(
        fixtures: 0,
        settled: 0,
        sides: {},
      );
    }

    await w.run(DateTime.utc(2026, 11, 22, 21));

    final carried = _onDay(w, 23);
    expect(
      [for (final s in carried) '${s.step.place}${s.step.round.wire}'],
      ['2semi', '3semi'],
    );
    for (final c in carried) {
      final before = semis.singleWhere((s) => s.step == c.step);
      expect(c.attempt, 2);
      expect(
        [for (final p in c.pairs) (p.home, p.away)],
        [for (final p in before.pairs) (p.home, p.away)],
      );
    }
  });

  test('a run repeated changes nothing', () async {
    final w = _World();
    await w.run(night19);
    final again = await w.run(night19);

    expect(again.entered, 0);
    expect(again.scheduled, 0);
    expect(w.cups.stages, hasLength(1));
    expect(w.cups.entries, hasLength(12));
  });

  test('turned off by the host: nothing at all', () async {
    final w = _World();
    final job = RunH2hCup(
      cups: w.cups,
      rounds: w.roundStore,
      leagues: w.leagues,
      sheets: w.sheets,
      idGenerator: w.ids,
      enabled: false,
    );

    final result = await job(now: night19);

    expect((result as Ok<H2hCupRun>).value.entered, 0);
    expect(w.cups.entries, isEmpty);
  });
}
