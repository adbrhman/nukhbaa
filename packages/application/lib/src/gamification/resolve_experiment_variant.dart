/// Use-case: which arm of an experiment a user is in (P1-8).
library;

import 'package:application/src/gamification/ports/experiment_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Answers the arm [ResolveExperimentVariant.call] should make the server
/// behave as, assigning the user on their first exposure.
///
/// **It cannot fail.** Every other use-case returns a [Result]; this one
/// returns a bare [String], deliberately. A gate that can fail is a feature
/// that can break, and there is no sensible error for a caller to render: a
/// flag that is off, a flag that does not exist, and a database that did not
/// answer all mean the same thing to the code downstream -- behave as you did
/// yesterday. So every one of them answers [VariantAllocator.control], and
/// the fallback lives here once instead of at every call site.
///
/// A transient failure costs nothing durable: no row is written, and the next
/// exposure resolves again. The cost is a user counted as `control` for one
/// request while their stored arm says otherwise, which is why the read is
/// never cached.
///
/// **Order.** The flag is read first, so a stopped experiment writes nothing:
/// assignments are the record of who was measured, and a flag that is off
/// measures no one.
final class ResolveExperimentVariant {
  /// Creates the use-case over its repository.
  const ResolveExperimentVariant({required ExperimentRepository experiments})
    : _experiments = experiments;

  final ExperimentRepository _experiments;

  /// The arm [userId] is in for [flagKey], allocating over [arms] on first
  /// exposure.
  ///
  /// A stored variant is returned as it stands even when it names no arm in
  /// [arms]: the row is the record of what the user was actually shown, and
  /// an arm removed from the code does not retract what was measured. Callers
  /// therefore treat any unrecognised variant as control.
  Future<String> call({
    required UserId userId,
    required String flagKey,
    required List<ExperimentArm> arms,
  }) async {
    final enabled = await _experiments.isFlagEnabled(flagKey);
    if (enabled is! Ok<bool> || !enabled.value) {
      return VariantAllocator.control;
    }

    final existing = await _experiments.readAssignment(
      userId: userId,
      flagKey: flagKey,
    );
    if (existing is! Ok<String?>) {
      return VariantAllocator.control;
    }
    final String? held = existing.value;
    if (held != null) {
      return held;
    }

    final String drawn = VariantAllocator.allocate(
      userId: userId.value,
      flagKey: flagKey,
      arms: arms,
    );
    final stored = await _experiments.assign(
      userId: userId,
      flagKey: flagKey,
      variant: drawn,
    );
    if (stored is! Ok<String>) {
      // The draw is not kept in memory: an arm that was never stored was
      // never assigned, and the next exposure draws the same one anyway.
      return VariantAllocator.control;
    }
    return stored.value;
  }
}
