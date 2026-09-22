import 'package:domain/src/identity/user_id.dart';

/// Who passed whom in one weekly-league group between two looks
/// (plan P3-4c).
///
/// A member is overtaken when they rank lower now than at the previous
/// look; the overtaker named is the nearest member now above them who was
/// below them before. A member with no previous rank is never a victim and
/// never an overtaker: their first look only sets the mark.
///
/// Pure: ranks in, pairs out.
final class OvertakeDetector {
  const OvertakeDetector._();

  /// Maps each overtaken member to the member who passed them.
  ///
  /// [previous] is the rank (1-based) each member had at the last look;
  /// [ordered] is the group now, best first.
  static Map<UserId, UserId> detect({
    required Map<UserId, int> previous,
    required List<UserId> ordered,
  }) {
    final passed = <UserId, UserId>{};
    for (var i = 0; i < ordered.length; i++) {
      final UserId victim = ordered[i];
      final int? before = previous[victim];
      if (before == null || i + 1 <= before) {
        continue;
      }
      for (var j = i - 1; j >= 0; j--) {
        final int? otherBefore = previous[ordered[j]];
        if (otherBefore != null && otherBefore > before) {
          passed[victim] = ordered[j];
          break;
        }
      }
    }
    return passed;
  }
}
