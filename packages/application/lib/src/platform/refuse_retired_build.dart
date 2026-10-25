/// Use-case: whether a player's request comes from a retired build that the
/// server must refuse while the owner's switch is on (scripts 149-150).
library;

import 'package:application/src/platform/ports/retired_build_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Decides the refusal of a request that names no build (asked by the owner
/// on 2026-10-26: the update for the 36 players on the oldest builds first,
/// nobody else).
///
/// While [enabled] -- `NUKHBA_REFUSE_RETIRED_BUILDS=on` on Northflank,
/// [switchedOn] -- a player whose app is older than the head-to-head tab
/// ([retiredBefore]) is refused: those builds know no update screen of their
/// own. It does not depend on the dashboard's minimum, which every build
/// since batch 147 obeys with its own update screen: the two are switched
/// apart, so the oldest builds can be retired alone. The caller asks only for
/// a request with no build header -- a build that names itself is never
/// retired.
///
/// Switched off, or an unreadable list: nobody is refused.
///
/// Never throws.
final class RefuseRetiredBuild {
  /// Creates the use-case over [players].
  RefuseRetiredBuild({
    required bool enabled,
    required RetiredBuildReader players,
    DateTime? before,
  }) : _enabled = enabled,
       _players = players,
       _before = before ?? retiredBefore;

  /// Whether the value of `NUKHBA_REFUSE_RETIRED_BUILDS` ([raw]) switches
  /// the refusal on: `on`, `true`, `yes` or `1`, in any case. Absent or
  /// anything else is off.
  static bool switchedOn(String? raw) => switch (raw?.trim().toLowerCase()) {
    'on' || 'true' || 'yes' || '1' => true,
    _ => false,
  };

  /// The head-to-head tab's release (batch 5, 2026-10-10 00:00 Riyadh): a
  /// build first seen before it shows «توقعاتي» in its bottom bar.
  static final DateTime retiredBefore = DateTime.utc(2026, 10, 9, 21);

  final bool _enabled;
  final RetiredBuildReader _players;
  final DateTime _before;

  /// Whether [userId]'s request, which named no build, is refused.
  Future<bool> call(UserId userId) async {
    if (!_enabled) {
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
