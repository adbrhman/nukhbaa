/// Deterministic allocation of a user to an experiment arm (P1-8).
library;

import 'dart:convert';

/// One arm of an experiment: a [name] and the share of the population it
/// takes, relative to the other arms.
///
/// The name is free text because `gamification.experiment_assignments.variant`
/// is (migration 0054), so an experiment may have more than two arms. The
/// convention recorded there is `control` for the arm that sees today's
/// behaviour.
final class ExperimentArm {
  /// Creates an arm. A [weight] of zero or less is ignored by
  /// [VariantAllocator.allocate] rather than rejected: an arm switched off by
  /// setting its weight to zero should not crash a running server.
  const ExperimentArm({required this.name, required this.weight});

  /// The stored variant name.
  final String name;

  /// This arm's share, relative to the sum of all the arms' weights.
  final int weight;
}

/// Decides which arm a user falls in, from the user and the flag alone.
///
/// **Why deterministic when the assignment is stored anyway.** The stored row
/// is the truth -- `(user_id, flag_key)` is the primary key, so a user keeps
/// the arm they were first given. This allocator only decides the arm of a
/// user who has none yet. Making that decision a pure function of
/// `flag_key:user_id` means two servers racing on the same first request
/// compute the same answer, so the row the race stores is the row either of
/// them would have stored.
///
/// **The hash is part of the contract.** Changing it, or the order or weights
/// of the arms, re-buckets only users who have no row yet; everyone already
/// assigned keeps their arm. That is the intended asymmetry: an experiment's
/// population may grow, it must never be re-drawn.
///
/// **Server-side only.** The FNV-1a step shifts past JavaScript's safe
/// integer range, so this must not be compiled for the web. `apps/mobile`
/// does not depend on `domain` (ADR-002), which is what keeps that true.
abstract final class VariantAllocator {
  /// The arm that sees today's behaviour, and the answer whenever there is
  /// nothing to allocate.
  static const String control = 'control';

  /// The arm [userId] falls in for [flagKey], given [arms].
  ///
  /// Returns [control] when no arm carries a positive weight: an experiment
  /// with nothing to split is not a reason to fail a request.
  static String allocate({
    required String userId,
    required String flagKey,
    required List<ExperimentArm> arms,
  }) {
    var total = 0;
    for (final ExperimentArm arm in arms) {
      if (arm.weight > 0) {
        total += arm.weight;
      }
    }
    if (total <= 0) {
      return control;
    }

    final int bucket = _fnv1a32('$flagKey:$userId') % total;
    var cursor = 0;
    for (final ExperimentArm arm in arms) {
      if (arm.weight <= 0) {
        continue;
      }
      cursor += arm.weight;
      if (bucket < cursor) {
        return arm.name;
      }
    }
    // Unreachable: the walk covers [0, total) and bucket is in that range.
    return control;
  }

  /// FNV-1a, 32-bit, over the UTF-8 bytes of [text].
  ///
  /// Chosen over [Object.hashCode] because that is not stable across
  /// processes or SDK versions, and an allocation that moves between restarts
  /// is not an allocation.
  static int _fnv1a32(String text) {
    var hash = 0x811c9dc5;
    for (final int byte in utf8.encode(text)) {
      hash ^= byte;
      hash =
          (hash +
              ((hash << 1) +
                  (hash << 4) +
                  (hash << 7) +
                  (hash << 8) +
                  (hash << 24))) &
          0xFFFFFFFF;
    }
    return hash;
  }
}
