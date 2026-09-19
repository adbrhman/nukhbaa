import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('FixturePointEntry.create', () {
    test('creates a valid fixtureScore credit', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: 6,
        sourceRef: 'fixture_score:f1:p1',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<FixturePointEntry>>());
    });

    test('rejects a non-UTC occurredAt', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: 3,
        sourceRef: 'fixture_score:f1:p1',
        occurredAt: DateTime(2026, 8, 1),
      );
      expect(result, isA<Err<FixturePointEntry>>());
      expect(
        (result as Err<FixturePointEntry>).error.code,
        'ledger.entry_occurred_at_not_utc',
      );
    });

    test('rejects a negative amount for a fixtureScore credit', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: -1,
        sourceRef: 'fixture_score:f1:p1',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Err<FixturePointEntry>>());
      expect(
        (result as Err<FixturePointEntry>).error.code,
        'ledger.entry_amount_negative',
      );
    });

    test('allows a negative amount for a correction', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.correction,
        amount: -3,
        sourceRef: 'correction:justification',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<FixturePointEntry>>());
    });

    test('rejects an empty sourceRef', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: 3,
        sourceRef: '',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Err<FixturePointEntry>>());
      expect(
        (result as Err<FixturePointEntry>).error.code,
        'ledger.entry_source_ref_empty',
      );
    });
  });

  group('EntryKind.fixtureScore', () {
    test('round-trips through wireValue/tryParse', () {
      expect(EntryKind.fixtureScore.wireValue, 'fixture_score');
      final parsed = EntryKind.tryParse('fixture_score');
      expect(parsed, isA<Ok<EntryKind>>());
      expect((parsed as Ok<EntryKind>).value, EntryKind.fixtureScore);
    });

    test('requires a non-negative amount', () {
      expect(EntryKind.fixtureScore.requiresNonNegativeAmount, isTrue);
    });

    test('is deduped per fixture, not per round', () {
      expect(EntryKind.fixtureScore.isDedupedPerFixture, isTrue);
      expect(EntryKind.fixtureScore.isDedupedPerRound, isFalse);
    });
  });

  group('EntryKind.streakBonus', () {
    Result<FixturePointEntry> bonus(int amount) => FixturePointEntry.create(
      id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
      participantId: const ParticipantId('participant-1'),
      fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
      kind: EntryKind.streakBonus,
      amount: amount,
      sourceRef: 'streak:7',
      occurredAt: DateTime.utc(2026, 9, 19),
    );

    test('round-trips through wireValue/tryParse', () {
      expect(EntryKind.streakBonus.wireValue, 'streak_bonus');
      final parsed = EntryKind.tryParse('streak_bonus');
      expect(parsed, isA<Ok<EntryKind>>());
      expect((parsed as Ok<EntryKind>).value, EntryKind.streakBonus);
    });

    test('is not deduped per fixture: it is not part of a fixture score', () {
      expect(EntryKind.streakBonus.isDedupedPerFixture, isFalse);
      expect(EntryKind.streakBonus.isDedupedPerRound, isFalse);
    });

    test('a bonus credit is valid and a negative one is rejected', () {
      expect(bonus(5), isA<Ok<FixturePointEntry>>());
      expect(
        (bonus(-1) as Err<FixturePointEntry>).error.code,
        'ledger.entry_amount_negative',
      );
    });
  });
}
