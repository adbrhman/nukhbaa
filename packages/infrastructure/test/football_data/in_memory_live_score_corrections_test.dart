import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

const _fixture = 'f1000000-0000-0000-0000-000000000018';

const _admin = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-0000000001c1'),
  role: PlatformRole.admin,
);

final class _Clock implements Clock {
  _Clock(this.now);
  DateTime now;

  @override
  DateTime nowUtc() => now;
}

/// The in-process boards as the composition root wires them: the poll
/// writes the provider's figures, an admin's correction lies over them.
void main() {
  test('a correction shows over the provider figure, and is forgotten after '
      'a day and a half', () {
    final clock = _Clock(DateTime.utc(2026, 10, 18, 16, 2));
    final provider = InMemoryLiveScoreBoard(now: () => clock.now);
    final corrections = InMemoryLiveScoreCorrections(now: () => clock.now);
    final board = CorrectedLiveScoreBoard(
      raw: provider,
      corrections: corrections,
    );
    final correct = AdminCorrectLiveScore(
      providerScores: provider,
      corrections: corrections,
      clock: clock,
    );

    board.put({
      _fixture: LiveScore(
        homeGoals: 2,
        awayGoals: 2,
        minute: 62,
        finished: false,
        updatedAt: clock.now,
      ),
    });
    expect(
      correct(
        principal: _admin,
        fixtureId: _fixture,
        homeGoals: 2,
        awayGoals: 1,
      ).isOk,
      isTrue,
    );

    final shown = board.read([_fixture])[_fixture]!;
    expect((shown.homeGoals, shown.awayGoals, shown.minute), (2, 1, 62));
    // The provider's own figure is kept as it is.
    final fed = provider.read([_fixture])[_fixture]!;
    expect((fed.homeGoals, fed.awayGoals), (2, 2));

    clock.now = clock.now.add(const Duration(hours: 31));
    expect(corrections.of(_fixture), isNull);
  });
}
