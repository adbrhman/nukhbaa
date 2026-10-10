import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hControlStore] (migration 0101): the settings
/// row, the excluded days, late seats and the admin log.
///
/// A late seat is an ordinary insert into `h2h_league_members`; 0100's own
/// constraints refuse a taken slot, a second seat for the same player in a
/// month, and a slot outside the group, and those refusals come back as
/// [ErrorKind.invariant] errors with stable codes.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hControlStore implements H2hControlStore {
  /// Creates the store over [_connection].
  const PostgresH2hControlStore(this._connection);

  final PostgresConnection _connection;

  static const String settingsSql = '''
SELECT auto_approve            AS auto_approve,
       auto_approve_lead_hours AS lead_hours,
       min_active_days         AS min_active_days,
       updated_by::text        AS updated_by,
       updated_at              AS updated_at
FROM gamification.h2h_settings
WHERE id
''';

  static const String saveSettingsSql = '''
UPDATE gamification.h2h_settings
SET auto_approve            = @auto_approve::boolean,
    auto_approve_lead_hours = @lead_hours::smallint,
    min_active_days         = @min_active_days::smallint,
    updated_by              = @updated_by::uuid,
    updated_at              = now()
WHERE id
''';

  static const String excludedDaysSql = '''
SELECT to_char(day, 'YYYY-MM-DD') AS day
FROM gamification.h2h_day_exclusions
WHERE day BETWEEN @from_day::date AND @through_day::date
ORDER BY day
''';

  static const String excludeSql = '''
INSERT INTO gamification.h2h_day_exclusions (day, excluded_by)
VALUES (@day::date, @excluded_by::uuid)
ON CONFLICT (day) DO NOTHING
RETURNING 1 AS excluded
''';

  static const String includeSql = '''
DELETE FROM gamification.h2h_day_exclusions
WHERE day = @day::date
RETURNING 1 AS included
''';

  static const String addSeatSql = '''
INSERT INTO gamification.h2h_league_members
  (league_id, month_start, user_id, slot)
VALUES (@league_id::uuid, @month::date, @user_id::uuid, @slot::smallint)
''';

  static const String recordSql = '''
INSERT INTO gamification.h2h_admin_actions (id, action, actor, detail)
VALUES (@id::uuid, @action::text, @actor::uuid, @detail::jsonb)
''';

  static const String recentSql = '''
SELECT id::text     AS id,
       action       AS action,
       actor::text  AS actor,
       detail::text AS detail,
       acted_at     AS acted_at
FROM gamification.h2h_admin_actions
ORDER BY acted_at DESC, id
LIMIT @limit::integer
''';

  @override
  Future<Result<H2hSettings>> settings() async {
    final result = await _connection.query(settingsSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      // 0101 inserts the row; without it, the rules of 0100 stand.
      return const Result.ok(H2hSettings.defaults);
    }
    final row = rows.single;
    final lead = _int(row['lead_hours']);
    final days = _int(row['min_active_days']);
    if (lead == null || days == null) {
      return Result.err(_corrupt('settings'));
    }
    return Result.ok(
      H2hSettings(
        autoApprove: row['auto_approve'] == true,
        leadHours: lead,
        minActiveDays: days,
        updatedBy: _userOf(row['updated_by']),
        updatedAt: _timestamp(row['updated_at']),
      ),
    );
  }

  @override
  Future<Result<void>> saveSettings({
    required bool autoApprove,
    required int leadHours,
    required int minActiveDays,
    required UserId by,
  }) async {
    final result = await _connection.query(
      saveSettingsSql,
      parameters: {
        'auto_approve': autoApprove,
        'lead_hours': leadHours,
        'min_active_days': minActiveDays,
        'updated_by': by.value,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(_reclassify(result.error));
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<Set<DateTime>>> excludedDays({
    required DateTime from,
    required DateTime through,
  }) async {
    final result = await _connection.query(
      excludedDaysSql,
      parameters: {'from_day': _isoDay(from), 'through_day': _isoDay(through)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final days = <DateTime>{};
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final day = _parseDay(row['day']);
      if (day == null) {
        return Result.err(_corrupt('exclusion'));
      }
      days.add(day);
    }
    return Result.ok(Set<DateTime>.unmodifiable(days));
  }

  @override
  Future<Result<bool>> exclude({
    required DateTime day,
    required UserId by,
  }) async {
    final result = await _connection.query(
      excludeSql,
      parameters: {'day': _isoDay(day), 'excluded_by': by.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    return Result.ok(
      (result as Ok<List<Map<String, dynamic>>>).value.isNotEmpty,
    );
  }

  @override
  Future<Result<bool>> include(DateTime day) async {
    final result = await _connection.query(
      includeSql,
      parameters: {'day': _isoDay(day)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    return Result.ok(
      (result as Ok<List<Map<String, dynamic>>>).value.isNotEmpty,
    );
  }

  @override
  Future<Result<void>> addSeat({
    required H2hLeagueId leagueId,
    required DateTime monthStart,
    required UserId userId,
    required int slot,
  }) async {
    final result = await _connection.query(
      addSeatSql,
      parameters: {
        'league_id': leagueId.value,
        'month': _isoDay(monthStart),
        'user_id': userId.value,
        'slot': slot,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(_reclassify(result.error));
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> record({
    required String id,
    required H2hAdminActionKind action,
    required UserId? by,
    required Map<String, Object?> detail,
  }) async {
    final result = await _connection.query(
      recordSql,
      parameters: {
        'id': id,
        'action': action.wireName,
        'actor': by?.value,
        'detail': jsonEncode(detail),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<List<H2hAdminAction>>> recentActions(int limit) async {
    final result = await _connection.query(
      recentSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final actions = <H2hAdminAction>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final kind = H2hAdminActionKind.ofWire(row['action']?.toString());
      final at = _timestamp(row['acted_at']);
      final id = row['id']?.toString();
      if (kind == null || at == null || id == null) {
        // A line this build does not know is left out, not guessed.
        continue;
      }
      actions.add(
        H2hAdminAction(
          id: id,
          action: kind,
          actor: _userOf(row['actor']),
          detail: _decode(row['detail']?.toString()) ?? const {},
          actedAt: at,
        ),
      );
    }
    return Result.ok(List<H2hAdminAction>.unmodifiable(actions));
  }

  /// The user stored as [raw]; null when there is none or it is unreadable.
  static UserId? _userOf(Object? raw) {
    final parsed = UserId.tryParse(raw?.toString());
    return parsed is Ok<UserId> ? parsed.value : null;
  }

  static Map<String, Object?>? _decode(String? raw) {
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Maps the 0100/0101 backstops to stable invariant codes.
  static AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    return switch (cause.constraintName) {
      'h2h_league_members_league_slot_uniq' => const AppError.invariant(
        'h2h.seat_taken',
        'This seat is taken',
      ),
      'h2h_league_members_month_user_uniq' ||
      'h2h_league_members_pkey' => const AppError.invariant(
        'h2h.player_seated',
        'This player already holds a seat this month',
      ),
      'h2h_league_members_slot_in_capacity' => const AppError.invariant(
        'h2h.seat_outside_group',
        'This seat is outside the group',
      ),
      'h2h_league_members_user_id_fkey' => const AppError.invariant(
        'h2h.player_unknown',
        'No such player',
      ),
      'h2h_settings_lead_range' ||
      'h2h_settings_active_days_range' => const AppError.validation(
        'h2h.settings_out_of_range',
        'A setting is out of its range',
      ),
      _ => error,
    };
  }

  static int? _int(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is BigInt && raw.isValidInt) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  static DateTime? _timestamp(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  static DateTime? _parseDay(Object? raw) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(raw?.toString() ?? '');
    if (match == null) {
      return null;
    }
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static String _isoDay(DateTime day) {
    final d = DateTime.utc(day.year, day.month, day.day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head $what row could not be read',
  );
}
