import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixtureLedgerRepository] over the append-only
/// `ledger.fixture_point_entries` table (Database ADR; migration
/// `0020_axiom4_fixture_ledger_social.sql`) — the per-fixture sibling of
/// [PostgresLedgerRepository].
///
/// Same atomicity/idempotency contract as [PostgresLedgerRepository]: the
/// whole batch is appended inside one transaction, deduped on
/// `(participant_id, fixture_id, entry_kind, source_ref)` via
/// `ON CONFLICT ON CONSTRAINT fixture_point_entries_fixture_score_uniq DO
/// NOTHING`. The adapter is total (never throws); SQL and rows never leak.
final class PostgresFixtureLedgerRepository implements FixtureLedgerRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixtureLedgerRepository(this._connection);

  final PostgresConnection _connection;

  static const String _insertEntrySql = '''
INSERT INTO ledger.fixture_point_entries
  (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
VALUES
  (@id, @participant_id, @fixture_id, @entry_kind, @amount, @source_ref, @occurred_at)
ON CONFLICT ON CONSTRAINT fixture_point_entries_fixture_score_uniq DO NOTHING
RETURNING id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at
''';

  @override
  Future<Result<List<FixturePointEntry>>> appendEntries(
    List<FixturePointEntry> entries,
  ) {
    if (entries.isEmpty) {
      return Future.value(const Result.ok(<FixturePointEntry>[]));
    }
    return _connection.runInTransaction((tx) async {
      final appended = <FixturePointEntry>[];
      for (final entry in entries) {
        final inserted = await tx.query(
          _insertEntrySql,
          parameters: {
            'id': entry.id.value,
            'participant_id': entry.participantId.value,
            'fixture_id': entry.fixture.value,
            'entry_kind': entry.kind.wireValue,
            'amount': entry.amount,
            'source_ref': entry.sourceRef,
            'occurred_at': entry.occurredAt.toUtc(),
          },
        );
        switch (inserted) {
          case Err<List<Map<String, dynamic>>>(:final error):
            return Result.err(_reclassify(error));
          case Ok<List<Map<String, dynamic>>>(:final value):
            if (value.isEmpty) {
              continue;
            }
            final mapped = _mapEntry(value.first);
            if (mapped is Err<FixturePointEntry>) {
              return Result.err(mapped.error);
            }
            appended.add((mapped as Ok<FixturePointEntry>).value);
        }
      }
      return Result.ok(List<FixturePointEntry>.unmodifiable(appended));
    });
  }

  static const String _selectByParticipantSql = '''
SELECT id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at
FROM ledger.fixture_point_entries
WHERE participant_id = @participant_id
ORDER BY occurred_at ASC, id ASC
''';

  @override
  Future<Result<List<FixturePointEntry>>> listEntries(
    ParticipantId participantId,
  ) async {
    final result = await _connection.query(
      _selectByParticipantSql,
      parameters: {'participant_id': participantId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapEntries(value),
    };
  }

  Result<List<FixturePointEntry>> _mapEntries(List<Map<String, dynamic>> rows) {
    final entries = <FixturePointEntry>[];
    for (final row in rows) {
      final mapped = _mapEntry(row);
      if (mapped is Err<FixturePointEntry>) {
        return Result.err(mapped.error);
      }
      entries.add((mapped as Ok<FixturePointEntry>).value);
    }
    return Result.ok(List<FixturePointEntry>.unmodifiable(entries));
  }

  Result<FixturePointEntry> _mapEntry(Map<String, dynamic> row) {
    final idResult = PointEntryId.tryParse(row['id']?.toString());
    final participantIdResult = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final kindResult = EntryKind.tryParse(row['entry_kind']?.toString());
    final amount = _readInt(row['amount']);
    final sourceRefRaw = row['source_ref'];
    final occurredAt = _readUtcTimestamp(row['occurred_at']);

    if (idResult is Err<PointEntryId>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    if (participantIdResult is Err<ParticipantId>) {
      return Result.err(
        _corrupt('participant_id', participantIdResult.error.message),
      );
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(_corrupt('fixture_id', fixtureResult.error.message));
    }
    if (kindResult is Err<EntryKind>) {
      return Result.err(_corrupt('entry_kind', kindResult.error.message));
    }
    if (amount == null) {
      return Result.err(_corrupt('amount', 'not an integer'));
    }
    if (sourceRefRaw is! String || sourceRefRaw.isEmpty) {
      return Result.err(_corrupt('source_ref', 'null or empty'));
    }
    if (occurredAt == null) {
      return Result.err(_corrupt('occurred_at', 'not a timestamp'));
    }

    return Result.ok(
      FixturePointEntry.fromStored(
        id: (idResult as Ok<PointEntryId>).value,
        participantId: (participantIdResult as Ok<ParticipantId>).value,
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        kind: (kindResult as Ok<EntryKind>).value,
        amount: amount,
        sourceRef: sourceRefRaw,
        occurredAt: occurredAt,
      ),
    );
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    const integrityCodes = {'23505', '23503', '23514'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    if (constraint == 'fixture_point_entries_participant_id_fkey') {
      return const AppError.invariant(
        'ledger.participant_not_found',
        'Participant not found',
      );
    }
    if (constraint == 'fixture_point_entries_fixture_score_uniq') {
      return const AppError.invariant(
        'ledger.already_posted',
        'This fixture-score credit was already appended',
      );
    }
    return const AppError.invariant(
      'ledger.integrity_violation',
      'The write violated a ledger integrity rule',
    );
  }

  static int? _readInt(Object? raw) {
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

  static DateTime? _readUtcTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed?.toUtc();
    }
    return null;
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'ledger.row_corrupt',
    'Stored fixture_point_entries row has invalid $field: $detail',
  );
}
