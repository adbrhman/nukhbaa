import 'package:shared/shared.dart';

/// Whether a fixture accepts new/amended predictions, computed — never
/// stored — from its own kickoff instant against a reference "now"
/// (docs/project-context.md, Axiom 4 Amendment: "Fixture locks and scores
/// individually at its own kickoff_at", replacing the round-wide
/// `RoundStatus.locked` transition).
///
/// A fixture is locked at and after its kickoff instant (inclusive), open
/// strictly before it. This is a pure comparison, not a stored state — there
/// is no "lock_fixture" command; the application layer (backed by the
/// `Clock` port) computes it fresh on every submit/amend and every scoring
/// pass. Pure and immutable.
final class FixtureLock {
  const FixtureLock._({required this.isLocked, required this.kickoffAt});

  /// Computes the lock state of a fixture kicking off at [kickoffAt], as of
  /// [nowUtc]. Both must already be UTC — callers own normalization; this
  /// stays a pure, total comparison (no exception escapes into a command
  /// path).
  static Result<FixtureLock> at({
    required DateTime kickoffAt,
    required DateTime nowUtc,
  }) {
    if (!kickoffAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'competition.fixture_lock_kickoff_not_utc',
          'Fixture kickoff instant must be UTC',
        ),
      );
    }
    if (!nowUtc.isUtc) {
      return const Result.err(
        AppError.validation(
          'competition.fixture_lock_now_not_utc',
          'The reference instant must be UTC',
        ),
      );
    }
    return Result.ok(
      FixtureLock._(
        isLocked: !nowUtc.isBefore(kickoffAt),
        kickoffAt: kickoffAt,
      ),
    );
  }

  /// True once [kickoffAt] has arrived or passed — no further submit/amend.
  final bool isLocked;

  /// The kickoff instant this lock state was computed against.
  final DateTime kickoffAt;

  @override
  bool operator ==(Object other) =>
      other is FixtureLock &&
      other.isLocked == isLocked &&
      other.kickoffAt == kickoffAt;

  @override
  int get hashCode => Object.hash(isLocked, kickoffAt);

  @override
  String toString() =>
      'FixtureLock(${isLocked ? 'locked' : 'open'} @ $kickoffAt)';
}
