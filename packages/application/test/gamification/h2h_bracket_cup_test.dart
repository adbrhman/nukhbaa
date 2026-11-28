// NK358_01
/// The Elite Cup as ONE bracket of sixteen through the real job (NK358_01,
/// owner decision 2026-11-28): December 2026 drawn in eight elite groups, the
/// first and the second place of each qualify, and the cup plays one round a
/// day on path 1 -- the round of sixteen, the quarter-finals, the semi-finals
/// and the final -- ending in one title. The reader that picks a player's cup
/// is asked too, from the same stored state.
library;

import 'dart:math';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _december = DateTime.utc(2026, 12);

H2hLeagueId _group(int g) =>
    H2hLeagueId('11111111-1111-4111-8111-00000000000$g');

H2hRoundId _rid(int n) =>
    H2hRoundId('22222222-2222-4222-8222-${n.toString().padLeft(12, '0')}');

/// Player s (slot 0..3) of elite group g (1..8).
UserId _p(int g, int s) => userNo(g * 10 + s);

/// Kickoff of a cup day: 15:00 UTC (18:00 Riyadh).
DateTime _kick(int day) => DateTime.utc(2026, 12, day, 15);

const _round16 = H2hCupStep(1, H2hCupRound.round16, bracket: true);
const _quarter = H2hCupStep(1, H2hCupRound.quarter, bracket: true);
const _semi = H2hCupStep(1, H2hCupRound.semi, bracket: true);
const _final = H2hCupStep(1, H2hCupRound.finale, bracket: true);

final class _Cups implements H2hCupStore {
  final List<H2hCupEntry> entries = <H2hCupEntry>[];
  final List<H2hCupStage> stages = <H2hCupStage>[];
  final List<H2hCupTitle> titles = <H2hCupTitle>[];
  final Map<String, H2hCupStageFigures> figures =
      <String, H2hCupStageFigures>{};

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async => Result.ok(
    H2hCupState(
      entries: List.of(entries),
      // As stagesSql reads them: day, then attempt.
      stages: List.of(stages)
        ..sort((a, b) {
          final byDay = a.day.compareTo(b.day);
          return byDay != 0 ? byDay : a.attempt.compareTo(b.attempt);
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
    // The database's backstop (0190, 0228): a later day than every stage,
    // and never an earlier cup day after a later one.
    if (stages.any((s) => !day.isAfter(s.day) || s.step.cupDay > step.cupDay)) {
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
    stages[i] = _replace(stages[i], lockedAt: DateTime.utc(2026, 12, 1));
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

/// December drawn in eight elite groups of four; 19 rounds approved, locked
/// and [judged] of them judged; in every group slot 0 is first, slot 1
/// second, slot 2 third and slot 3 fourth.
final class _World {
  _World({int judged = 19}) {
    leagues.months[_december] = H2hMonthInfo(
      monthStart: _december,
      isPilot: false,
      seatedCount: 32,
    );
    leagues.drawn[_december] = [
      for (var g = 1; g <= 8; g++)
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
    for (var n = 1; n <= 19; n++) {
      roundStore.addRound(
        H2hRound(
          id: _rid(n),
          monthStart: _december,
          number: n,
          day: DateTime.utc(2026, 12, n),
          fixtureCount: 8,
          approvedBy: null,
          lockedAt: DateTime.utc(2026, 12, n, 12),
        ),
      );
    }
    for (var g = 1; g <= 8; g++) {
      sheets.sheets[_group(g)] = H2hGroupSheet(
        members: [
          for (var s = 0; s < 4; s++)
            H2hMember(userId: _p(g, s), slot: s, joinedAt: _december),
        ],
        scores: [
          for (var n = 1; n <= 19; n++)
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
      roundStore.dayOf(DateTime.utc(2026, 12, d), 8, _kick(d));
    }
  }

  final leagues = FakeH2hLeagueStore();
  final roundStore = FakeH2hRoundStore();
  final sheets = FakeH2hSheetReader();
  final cups = _Cups();
  final controls = _Controls();
  final ids = SequenceIds();
  final List<H2hCupRun> runs = <H2hCupRun>[];

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
    final did = (result as Ok<H2hCupRun>).value;
    runs.add(did);
    return did;
  }

  int total(int Function(H2hCupRun) of) =>
      runs.fold(0, (sum, r) => sum + of(r));
}

/// Every pair of [stage] won by its home side.
Map<UserId, int> _homeWins(H2hCupStage stage) => {
  for (final p in stage.pairs) ...{p.home: 9, p.away: 3},
};

/// Plays the stage drawn for December [day]: frozen at its first kickoff,
/// settled with [points], judged that evening (which also draws the next
/// round for the next day).
Future<void> _play(
  _World w,
  int day, {
  Map<UserId, int> Function(H2hCupStage stage) points = _homeWins,
}) async {
  await w.run(DateTime.utc(2026, 12, day, 15, 30));
  final stage = w.cups.stages.last;
  expect(stage.day, DateTime.utc(2026, 12, day));
  expect(stage.locked, isTrue);
  w.cups.settle(stage, points(stage));
  await w.run(DateTime.utc(2026, 12, day, 21));
}

void main() {
  /// The evening of round 19: Riyadh's December 20 has begun.
  final night19 = DateTime.utc(2026, 12, 19, 21, 30);

  test('once the 19 rounds are judged: sixteen qualifiers, the first two of '
      'each of the eight groups, and the round of sixteen drawn apart on '
      'the next qualifying day', () async {
    final w = _World();

    final run = await w.run(night19);

    expect(run.entered, 16);
    expect(run.scheduled, 1);
    for (var g = 1; g <= 8; g++) {
      for (var s = 0; s < 2; s++) {
        final e = w.cups.entries.singleWhere((e) => e.userId == _p(g, s));
        expect(e.place, s + 1);
        expect(e.groupNumber, g);
      }
      expect(w.cups.entries.any((e) => e.userId == _p(g, 2)), isFalse);
      expect(w.cups.entries.any((e) => e.userId == _p(g, 3)), isFalse);
    }
    final stage = w.cups.stages.single;
    expect(stage.step, _round16);
    expect(stage.day, DateTime.utc(2026, 12, 20));
    expect(stage.pairs, hasLength(8));
    expect([for (final p in stage.pairs) p.slot], [1, 2, 3, 4, 5, 6, 7, 8]);
    final byUser = {for (final e in w.cups.entries) e.userId: e};
    for (final p in stage.pairs) {
      // A first place meets the second place of ANOTHER group.
      expect({byUser[p.home]!.place, byUser[p.away]!.place}, {1, 2});
      expect(byUser[p.home]!.groupNumber, isNot(byUser[p.away]!.groupNumber));
    }
    expect({
      for (final p in stage.pairs) ...[p.home, p.away],
    }, hasLength(16));
  });

  test('nothing before the 19th round is judged', () async {
    final w = _World(judged: 18);

    expect((await w.run(night19)).entered, 0);
    expect(w.cups.entries, isEmpty);
    expect(w.cups.stages, isEmpty);
  });

  test(
    'with automatic approval off the qualifiers are stored, no stage is',
    () async {
      final w = _World()..controls.autoApprove = false;

      final run = await w.run(night19);

      expect(run.entered, 16);
      expect(w.cups.stages, isEmpty);
    },
  );

  test('the whole bracket: one round a day, the winners meeting in the order '
      'of their slots, and one title', () async {
    final w = _World();
    await w.run(night19);
    for (final day in [20, 21, 22, 23]) {
      await _play(w, day);
    }

    final stages = w.cups.stages;
    expect(
      [for (final s in stages) s.step],
      [_round16, _quarter, _semi, _final],
    );
    expect([for (final s in stages) s.day.day], [20, 21, 22, 23]);
    expect([for (final s in stages) s.pairs.length], [8, 4, 2, 1]);
    expect(stages.every((s) => s.decided), isTrue);

    // The home side wins every pair, so the winner of slot k is the home
    // side of slot k, and the next round pairs them two by two.
    for (var r = 0; r < 3; r++) {
      final done = stages[r].pairs;
      final next = stages[r + 1].pairs;
      for (var i = 0; i < next.length; i++) {
        expect(next[i].slot, i + 1);
        expect(next[i].home, done[2 * i].home);
        expect(next[i].away, done[2 * i + 1].home);
      }
    }

    final finale = stages.last.pairs.single;
    final title = w.cups.titles.single;
    expect(title.place, 1);
    expect(title.champion, finale.home);
    expect(title.runnerUp, finale.away);
    expect(title.how, 'final');

    expect(w.total((r) => r.entered), 16);
    expect(w.total((r) => r.scheduled), 4);
    expect(w.total((r) => r.decided), 15);
    expect(w.total((r) => r.crowned), 1);

    // The cup is over with its one title: a later run does nothing.
    final later = await w.run(DateTime.utc(2026, 12, 24, 12));
    expect(later.scheduled + later.decided + later.crowned, 0);
    expect(w.cups.stages, hasLength(4));
  });

  test('a round waits for the one before it: nothing is drawn while the '
      'round of sixteen is not judged', () async {
    final w = _World();
    await w.run(night19);

    await w.run(DateTime.utc(2026, 12, 20, 15, 30));
    expect(w.cups.stages, hasLength(1));
    expect(w.cups.stages.single.locked, isTrue);
    await w.run(DateTime.utc(2026, 12, 20, 21));
    expect(w.cups.stages, hasLength(1));
    expect(w.cups.titles, isEmpty);
  });

  test('a pair nobody played leaves seven: the quarter-finals have three '
      'pairs and a bye, and the bracket still ends in a final', () async {
    final w = _World();
    await w.run(night19);
    // Slot 1 is predicted by neither side; every other pair is won by home.
    await _play(
      w,
      20,
      points: (stage) => {
        for (final p in stage.pairs.skip(1)) ...{p.home: 9, p.away: 3},
      },
    );
    final r16 = w.cups.stages.first;
    expect(r16.results.first.winner, isNull);
    expect(r16.results.first.outcome, H2hCupOutcome.bothAbsent.wire);
    final through = [for (final p in r16.pairs.skip(1)) p.home];
    expect(through, hasLength(7));

    await _play(w, 21);
    final quarter = w.cups.stages[1];
    expect(quarter.step, _quarter);
    expect(quarter.pairs, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(quarter.pairs[i].home, through[2 * i]);
      expect(quarter.pairs[i].away, through[2 * i + 1]);
    }
    // The odd one out, the winner of slot 8, is in none of the pairs.
    expect(
      quarter.pairs.any(
        (p) => p.home == through.last || p.away == through.last,
      ),
      isFalse,
    );

    await _play(w, 22);
    final semi = w.cups.stages[2];
    expect(semi.step, _semi);
    expect(semi.day, DateTime.utc(2026, 12, 22));
    expect(semi.pairs, hasLength(2));
    final won = [for (final p in quarter.pairs) p.home];
    expect(semi.pairs[0].home, won[0]);
    expect(semi.pairs[0].away, won[1]);
    expect(semi.pairs[1].home, won[2]);
    expect(semi.pairs[1].away, through.last, reason: 'the bye joins last');

    await _play(w, 23);
    final finale = w.cups.stages[3];
    expect(finale.step, _final);
    expect(finale.pairs.single.home, semi.pairs[0].home);
    expect(finale.pairs.single.away, semi.pairs[1].home);
    expect(w.cups.titles.single.champion, finale.pairs.single.home);
    // The pair nobody played is decided too (both lose): 8 + 3 + 2 + 1.
    expect(w.total((r) => r.decided), 8 + 3 + 2 + 1);
  });

  test('the player-facing reader finds the bracket from the same state: a '
      'qualifier reads his own cup, another player only watches', () async {
    final w = _World();
    await w.run(night19);
    final today = DateTime.utc(2026, 12, 20);

    final mine = await H2hCupMonthPicker.pick(
      cups: w.cups,
      today: today,
      user: _p(3, 1),
    );
    final own = (mine as Ok<H2hCupMonthPick?>).value!;
    expect(own.month, _december);
    expect(own.watching, isFalse);
    expect(own.groupNumber, 3);

    final other = await H2hCupMonthPicker.pick(
      cups: w.cups,
      today: today,
      user: _p(3, 2),
    );
    final watcher = (other as Ok<H2hCupMonthPick?>).value!;
    expect(watcher.month, _december);
    expect(watcher.watching, isTrue);
    expect(watcher.groupNumber, 0);
  });
}
