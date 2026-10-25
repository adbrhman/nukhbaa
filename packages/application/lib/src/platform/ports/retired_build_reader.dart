import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the players still on a retired app build (script 149).
///
/// A build is known by the sessions it reports (`ops.frame_reports`,
/// migration 0070): its first report dates it, and a player's newest report
/// names the build they use. Backed by `PostgresRetiredBuildReader`, held
/// in the process by `CachedRetiredBuildReader`.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class RetiredBuildReader {
  /// The players whose newest Android session ran a build first seen before
  /// [before].
  Future<Result<Set<UserId>>> playersOnBuildsBefore(DateTime before);
}
