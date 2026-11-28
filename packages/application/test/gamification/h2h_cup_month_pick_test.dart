// NK309_02
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
final _december = DateTime.utc(2026, 12);

/// The Elite Cups as stored, by month; every other month holds none.
final class _Cups implements H2hCupStore {
  _Cups(this.byMonth, {this.failure});

  final Map<DateTime, H2hCupState> byMonth;
  final AppError? failure;
  final List<DateTime> reads = <DateTime>[];

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async {
    reads.add(monthStart);
    final error = failure;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(byMonth[monthStart] ?? H2hCupState.empty);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

H2hCupEntry _entry(int user, int place, int group) => H2hCupEntry(
  userId: userNo(user),
  place: place,
  groupNumber: group,
  leaguePoints: 40,
  pointsFor: 100,
  exactCount: 10,
);

/// Path 1's four qualifiers are users 1-4 (groups 1-4); path 2's are 5-8.
List<H2hCupEntry> _entries({int pathOne = 4}) => [
  for (var g = 1; g <= pathOne; g++) _entry(g, 1, g),
  for (var g = 1; g <= 4; g++) _entry(4 + g, 2, g),
];

H2hCupState _open({int pathOne = 4}) => H2hCupState(
  entries: _entries(pathOne: pathOne),
  stages: const <H2hCupStage>[],
  titles: const <H2hCupTitle>[],
);

/// A cup whose three titles are decided and whose last stage was on [day].
H2hCupState _finished(DateTime day) => H2hCupState(
  entries: _entries(),
  stages: [
    H2hCupStage(
      id: const H2hCupStageId('55555555-5555-4555-8555-555555555555'),
      monthStart: _november,
      step: H2hCupStep(1, H2hCupRound.finale),
      attempt: 1,
      day: day,
      fixtureCount: 8,
      lockedAt: day,
      pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(2))],
      results: const <H2hCupResult>[],
    ),
  ],
  titles: [
    for (var place = 1; place <= 3; place++)
      H2hCupTitle(
        place: place,
        champion: userNo(place),
        runnerUp: null,
        how: 'final',
      ),
  ],
);

Future<H2hCupMonthPick?> _pick(
  _Cups cups, {
  required DateTime today,
  required int user,
}) async {
  final result = await H2hCupMonthPicker.pick(
    cups: cups,
    today: today,
    user: userNo(user),
  );
  return (result as Ok<H2hCupMonthPick?>).value;
}

void main() {
  group('H2hCupMonthPicker', () {
    test('a qualifier reads his own path and group', () async {
      final pick = await _pick(
        _Cups({_november: _open()}),
        today: DateTime.utc(2026, 11, 22),
        user: 3,
      );

      expect(pick, isNotNull);
      expect(pick!.month, _november);
      expect(pick.place, 1);
      expect(pick.groupNumber, 3);
      expect(pick.watching, isFalse);
      expect(pick.state.entries, hasLength(8));
    });

    test('a player outside the cup watches the first places path', () async {
      final pick = await _pick(
        _Cups({_november: _open()}),
        today: DateTime.utc(2026, 11, 22),
        user: 99,
      );

      expect(pick!.watching, isTrue);
      expect(pick.place, H2hCupMonthPicker.spectatorPlace);
      expect(pick.groupNumber, 0);
    });

    test('with no first-place qualifier there is nothing to read', () async {
      final pick = await _pick(
        _Cups({_november: _open(pathOne: 0)}),
        today: DateTime.utc(2026, 11, 22),
        user: 99,
      );

      expect(pick, isNull);
    });

    test('the cup he is in wins over the current one he could watch', () async {
      final cups = _Cups({
        _november: _open(),
        _december: H2hCupState(
          entries: [_entry(50, 1, 1), _entry(51, 1, 2)],
          stages: const <H2hCupStage>[],
          titles: const <H2hCupTitle>[],
        ),
      });
      final pick = await _pick(cups, today: DateTime.utc(2026, 12, 2), user: 2);

      expect(pick!.month, _november);
      expect(pick.watching, isFalse);
      expect(pick.place, 1);
    });

    test('of two cups to watch, the current month wins', () async {
      final pick = await _pick(
        _Cups({_november: _open(), _december: _open()}),
        today: DateTime.utc(2026, 12, 2),
        user: 99,
      );

      expect(pick!.month, _december);
      expect(pick.watching, isTrue);
    });

    test('a month before the elite draw is never read', () async {
      final cups = _Cups({_november: _open()});
      await _pick(cups, today: DateTime.utc(2026, 11, 22), user: 1);

      expect(cups.reads, [_november]);
    });

    test('a finished cup stays three days and is gone on the fourth', () async {
      final cups = _Cups({_november: _finished(DateTime.utc(2026, 11, 22))});

      final third = await _pick(
        cups,
        today: DateTime.utc(2026, 11, 25),
        user: 1,
      );
      expect(third, isNotNull);

      final fourth = await _pick(
        cups,
        today: DateTime.utc(2026, 11, 26),
        user: 1,
      );
      expect(fourth, isNull);
    });

    test('a cup with a title still open is never over', () {
      final state = H2hCupState(
        entries: _entries(),
        stages: const <H2hCupStage>[],
        titles: [
          H2hCupTitle(
            place: 1,
            champion: userNo(1),
            runnerUp: null,
            how: 'final',
          ),
        ],
      );

      // NK359_01e
      expect(
        H2hCupMonthPicker.isOver(
          state,
          DateTime.utc(2027),
          month: DateTime.utc(2026, 11),
        ),
        isFalse,
      );
    });

    test('entryOf finds a qualifier and nobody else', () {
      final state = _open();

      expect(H2hCupMonthPicker.entryOf(state, userNo(6))?.place, 2);
      expect(H2hCupMonthPicker.entryOf(state, userNo(99)), isNull);
    });

    test('a failing store is returned as it came', () async {
      const failure = AppError.transient('db.down', 'the store is down');
      final result = await H2hCupMonthPicker.pick(
        cups: _Cups(const <DateTime, H2hCupState>{}, failure: failure),
        today: DateTime.utc(2026, 11, 22),
        user: userNo(1),
      );

      expect(result, isA<Err<H2hCupMonthPick?>>());
      expect((result as Err<H2hCupMonthPick?>).error, failure);
    });
  });
}
