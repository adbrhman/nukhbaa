import 'package:shared/shared.dart';

/// Port that gives each head-to-head group its secret order of the
/// round-robin's turns (migration 0184).
///
/// Backed by `PostgresH2hTurnKeeper`. The draw and the extra groups write
/// the order in the transaction that opens the group; this port catches up
/// the groups opened before 0184, and is run before any round is locked. A
/// group whose member was seated before a round of its month locked keeps
/// the order of the slots: its rounds may already have been played in it.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hTurnKeeper {
  /// Gives every group of the month opened by [monthStart] that may take
  /// one, and has none, its secret order. Returns how many were given one.
  Future<Result<int>> ensureTurns(DateTime monthStart);
}
