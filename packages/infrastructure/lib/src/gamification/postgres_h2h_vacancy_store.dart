import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [H2hVacancyStore] (NK278, migration 0214).
///
/// **A vacancy** and, when a player of the waiting list qualifies, its fill
/// are written in ONE transaction ([vacate]): both rows or neither, so a
/// player never leaves his seat without the record that sends him to the
/// waiting list, and a seat is never filled without its vacancy. The 0214
/// guards (one move a round, one relegation a month, no return, the seat's
/// holder, a vacant seat, a waiting seat held, a round not started) arrive
/// as constraint violations and are returned as the invariant
/// `h2h.move_refused`, which the absence job skips.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresH2hVacancyStore implements H2hVacancyStore {
  /// Creates the store over [_connection].
  const PostgresH2hVacancyStore(this._connection);

  final PostgresConnection _connection;

  /// The month's vacancies, oldest first, each with its fill.
  static const String vacanciesSql = '''
SELECT v.id::text        AS id,
       v.league_id::text AS league_id,
       v.slot            AS slot,
       v.out_user::text  AS out_user,
       v.from_round      AS from_round,
       f.in_user::text   AS in_user,
       f.from_round      AS filled_from
FROM gamification.h2h_seat_vacancies v
LEFT JOIN gamification.h2h_vacancy_fills f ON f.vacancy_id = v.id
WHERE v.month_start = @month::date
ORDER BY v.created_at, v.id
''';

  /// A seat left for absence.
  static const String insertVacancySql = '''
INSERT INTO gamification.h2h_seat_vacancies
  (id, month_start, league_id, slot, out_user, from_round, kind,
   absent_rounds)
VALUES (@id::uuid, @month::date, @league_id::uuid, @slot::smallint,
        @out_user::uuid, @from_round::smallint, 'absence',
        @absent_rounds::jsonb)
''';

  /// A vacant seat taken by a player of the waiting list.
  static const String insertFillSql = '''
INSERT INTO gamification.h2h_vacancy_fills
  (vacancy_id, month_start, in_user, from_round, from_league_id, from_slot,
   candidate)
VALUES (@vacancy_id::uuid, @month::date, @in_user::uuid,
        @from_round::smallint, @from_league_id::uuid, @from_slot::smallint,
        @candidate::jsonb)
''';

  @override
  Future<Result<List<H2hSeatVacancy>>> vacanciesOf(DateTime monthStart) async {
    final month = _dayOf(monthStart);
    final result = await _connection.query(
      vacanciesSql,
      parameters: {'month': _isoDay(month)},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final out = <H2hSeatVacancy>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final id = row['id']?.toString();
      final league = H2hLeagueId.tryParse(row['league_id']?.toString());
      final slot = _int(row['slot']);
      final user = UserId.tryParse(row['out_user']?.toString());
      final from = _int(row['from_round']);
      final inRaw = row['in_user'];
      final inUser = inRaw == null ? null : UserId.tryParse(inRaw.toString());
      final filledRaw = row['filled_from'];
      final filledFrom = filledRaw == null ? null : _int(filledRaw);
      if (id == null ||
          league is Err<H2hLeagueId> ||
          slot == null ||
          user is Err<UserId> ||
          from == null ||
          inUser is Err<UserId> ||
          (filledRaw != null && filledFrom == null)) {
        return Result.err(_corrupt('vacancy'));
      }
      out.add(
        H2hSeatVacancy(
          id: id,
          monthStart: month,
          leagueId: (league as Ok<H2hLeagueId>).value,
          slot: slot,
          outUser: (user as Ok<UserId>).value,
          fromRound: from,
          filledBy: inUser is Ok<UserId> ? inUser.value : null,
          filledFrom: filledFrom,
        ),
      );
    }
    return Result.ok(List<H2hSeatVacancy>.unmodifiable(out));
  }

  @override
  Future<Result<void>> vacate({
    required H2hSeatVacancy vacancy,
    H2hVacancyFill? fill,
  }) async {
    final result = await _connection.runInTransaction<void>((tx) async {
      final left = await tx.query(
        insertVacancySql,
        parameters: {
          'id': vacancy.id,
          'month': _isoDay(vacancy.monthStart),
          'league_id': vacancy.leagueId.value,
          'slot': vacancy.slot,
          'out_user': vacancy.outUser.value,
          'from_round': vacancy.fromRound,
          'absent_rounds': jsonEncode([
            for (final r in vacancy.absentRounds)
              {'month': _isoDay(r.month), 'round': r.round},
          ]),
        },
      );
      if (left is Err<List<Map<String, dynamic>>>) {
        return Result.err(left.error);
      }
      if (fill != null) {
        final taken = await tx.query(
          insertFillSql,
          parameters: _fillParameters(fill),
        );
        if (taken is Err<List<Map<String, dynamic>>>) {
          return Result.err(taken.error);
        }
      }
      return const Result.ok(null);
    });
    return switch (result) {
      Err<void>(:final error) => Result.err(_refusal(error)),
      Ok<void>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<void>> fill(H2hVacancyFill fill) async {
    final result = await _connection.query(
      insertFillSql,
      parameters: _fillParameters(fill),
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _refusal(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  static Map<String, Object?> _fillParameters(H2hVacancyFill fill) {
    final facts = fill.facts;
    return {
      'vacancy_id': fill.vacancyId,
      'month': _isoDay(fill.monthStart),
      'in_user': fill.inUser.value,
      'from_round': fill.fromRound,
      'from_league_id': fill.fromLeagueId.value,
      'from_slot': fill.fromSlot,
      'candidate': jsonEncode(
        facts == null
            ? const <String, Object?>{}
            : <String, Object?>{
                'user_id': facts.userId.value,
                'missed': facts.missed,
                'predicted': facts.predicted,
                'points': facts.points,
                'exact': facts.exact,
                'outcomes': facts.outcomes,
                'active_days': facts.activeDays,
                'window_days': H2hAbsencePolicy.windowDays,
              },
      ),
    };
  }

  /// The 0214 refusals: one invariant code for the job.
  static AppError _refusal(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final name = cause.constraintName ?? '';
    if (name.startsWith('h2h_seat_vacancies_') ||
        name.startsWith('h2h_vacancy_fills_') ||
        name == 'h2h_one_move_per_round' ||
        name == 'h2h_one_relegation_a_month' ||
        name == 'h2h_no_return_in_month') {
      return AppError.invariant(
        'h2h.move_refused',
        'The vacancy or its fill was refused: $name',
      );
    }
    return error;
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

  static DateTime _dayOf(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);

  static String _isoDay(DateTime day) {
    final d = _dayOf(day);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static AppError _corrupt(String what) => AppError.transient(
    'gamification.h2h_row_corrupt',
    'A stored head-to-head $what row could not be read',
  );
}
