// NK310_01
/// Read port for the owners' view of the Elite Cup's fixtures and picks
/// (script 310).
///
/// Backed by `PostgresH2hCupPickReader` (script 311), which implements this
/// beside `H2hCupPickReader`. Unlike that port it **withholds nothing**:
/// every player's pick on every fixture comes back, before kickoff too. It
/// is a separate interface so that the use-case a player or an admin reaches
/// (`GetH2hCupBoard`) is never handed a reader that can leak. Only
/// `GetOwnerH2hCupPicks`, behind the owners' gate, takes this one.
///
/// A locked stage's fixtures are its frozen list; an unlocked stage's are
/// the visible, non-test fixtures of its day as they stand now. A fixture
/// that left the stage's day, was hidden or is a test fixture comes back
/// with `counted` false.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
library;

import 'package:application/src/gamification/ports/h2h_cup_pick_reader.dart';
import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the fixtures of cup stages with every player's picks.
abstract interface class H2hCupOwnerPickReader {
  /// The fixtures of every stage of [stages], by kickoff (none registered
  /// last), keyed by stage id, in one reading. A stage with no fixture maps
  /// to an empty list. The picks are those of the players of the stage's
  /// pairs, all of them, whatever the kickoff.
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>>
  fixturesOfUnmasked({required List<H2hCupStage> stages});
}
