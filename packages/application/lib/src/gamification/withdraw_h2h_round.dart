import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: an admin withdraws a mistaken round (migration 0100).
///
/// Only the last round of a month, and only before its first kickoff froze
/// it: the store returns an invariant error otherwise. Numbering stays
/// gap-free, and nobody's played round disappears.
///
/// Never throws; returns a typed [Result].
final class WithdrawH2hRound {
  /// Creates the use-case over its store.
  const WithdrawH2hRound({required H2hRoundStore rounds}) : _rounds = rounds;

  final H2hRoundStore _rounds;

  /// Withdraws [roundId] for [principal], an admin.
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required H2hRoundId roundId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _rounds.withdraw(roundId);
  }
}
