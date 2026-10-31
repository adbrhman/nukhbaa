/// The Elite Cup through the real job (NK185, migration 0190): the
/// qualifiers once the 19 rounds are judged, the stages one after the other
/// on the next qualifying days, the decisions, the titles, a stage carried
/// to another day, and nothing before the league is finished.
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
      stages: List.of(stages)..sort((a, b) => a.day.compareTo(b.day)),
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
    // The database's backstop: a later day than every stage.
    if (stages.any((s) => !s.day.isBefore(day))) {
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
      'the title and path 2 drawn', () async {
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
    final path2 = w.cups.stages.last;
    expect(path2.step, const H2hCupStep(2, H2hCupRound.semi));
    expect(path2.day, DateTime.utc(2026, 11, 22));
    expect(
      {
        for (final p in path2.pairs) ...[p.home, p.away],
      },
      {_p(1, 1), _p(2, 1), _p(3, 1), _p(4, 1)},
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
    // Path 1 needs no final: path 2 is drawn next.
    expect(w.cups.stages.last.step, const H2hCupStep(2, H2hCupRound.semi));
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
