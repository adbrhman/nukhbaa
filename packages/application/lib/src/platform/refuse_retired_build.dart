/// Use-case: whether a player's request comes from a retired build that the
/// server must refuse while an admin holds a minimum (script 149).
library;

import 'package:application/src/platform/ports/app_update_policy_store.dart';
import 'package:application/src/platform/ports/retired_build_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Decides the refusal of a request that names no build (asked by the owner
/// on 2026-10-26).
///
/// While an admin holds a minimum (the dashboard's «ارفع الحد الأدنى»,
/// migration 0113), the builds that know it show their own update screen;
/// the builds older than the head-to-head tab ([retiredBefore]) know none,
/// and only the server's refusal reaches them. Those players alone are
/// refused: a build between the tab and the minimum (11-14 October) is
/// served as before. The caller asks only for a request with no build
/// header -- a build that names itself is never retired.
///
/// No minimum, an unreadable one, or an unreadable list: nobody is refused.
///
/// Never throws.
final class RefuseRetiredBuild {
  /// Creates the use-case over [policy] and [players].
  RefuseRetiredBuild({
    required AppUpdatePolicyStore policy,
    required RetiredBuildReader players,
    DateTime? before,
  }) : _policy = policy,
       _players = players,
       _before = before ?? retiredBefore;

  /// The head-to-head tab's release (batch 5, 2026-10-10 00:00 Riyadh): a
  /// build first seen before it shows «توقعاتي» in its bottom bar.
  static final DateTime retiredBefore = DateTime.utc(2026, 10, 9, 21);

  final AppUpdatePolicyStore _policy;
  final RetiredBuildReader _players;
  final DateTime _before;

  /// Whether [userId]'s request, which named no build, is refused.
  Future<bool> call(UserId userId) async {
    final Result<int?> minimum = await _policy.minSupportedBuild();
    if (minimum is! Ok<int?> || minimum.value == null) {
      return false;
    }
    final Result<Set<UserId>> players = await _players.playersOnBuildsBefore(
      _before,
    );
    return switch (players) {
      Ok<Set<UserId>>(:final value) => value.contains(userId),
      Err<Set<UserId>>() => false,
    };
  }
}
