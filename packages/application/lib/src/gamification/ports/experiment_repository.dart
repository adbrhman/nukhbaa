import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read/write port for feature flags and their assignments (migration 0054).
///
/// General contract (Application ADR §2): never throws, maps driver failures
/// to [ErrorKind.transient].
///
/// Backend-only by design: nothing here is ever answered to a client. A
/// client receives the behaviour the server decided, never the flag it was
/// decided from -- a client that can read its arm can choose it, and an
/// experiment whose subjects choose their arm measures nothing.
abstract interface class ExperimentRepository {
  /// Whether [flagKey] exists and is switched on.
  ///
  /// A flag that is absent is not an error: it answers `false`, which is what
  /// "this experiment has not been started" means.
  Future<Result<bool>> isFlagEnabled(String flagKey);

  /// The variant [userId] already holds for [flagKey], or `null` when they
  /// hold none.
  Future<Result<String?>> readAssignment({
    required UserId userId,
    required String flagKey,
  });

  /// Stores [variant] for ([userId], [flagKey]) unless a row is already
  /// there, and answers the variant that is stored afterwards.
  ///
  /// Never overwrites: the primary key is what makes an assignment stable, so
  /// the loser of a race gets the winner's variant back rather than its own.
  Future<Result<String>> assign({
    required UserId userId,
    required String flagKey,
    required String variant,
  });
}
