import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  final kickoff = DateTime.utc(2026, 8, 1, 18);

  group('FixtureLock.at', () {
    test('is open strictly before kickoff', () {
      final result = FixtureLock.at(
        kickoffAt: kickoff,
        nowUtc: kickoff.subtract(const Duration(minutes: 1)),
      );
      expect(result, isA<Ok<FixtureLock>>());
      expect((result as Ok<FixtureLock>).value.isLocked, isFalse);
    });

    test('is locked exactly at kickoff (inclusive)', () {
      final result = FixtureLock.at(kickoffAt: kickoff, nowUtc: kickoff);
      expect((result as Ok<FixtureLock>).value.isLocked, isTrue);
    });

    test('is locked after kickoff', () {
      final result = FixtureLock.at(
        kickoffAt: kickoff,
        nowUtc: kickoff.add(const Duration(minutes: 1)),
      );
      expect((result as Ok<FixtureLock>).value.isLocked, isTrue);
    });

    test('rejects a non-UTC kickoff instant', () {
      final result = FixtureLock.at(
        kickoffAt: DateTime(2026, 8, 1, 18),
        nowUtc: DateTime.now().toUtc(),
      );
      expect(result, isA<Err<FixtureLock>>());
      expect(
        (result as Err<FixtureLock>).error.code,
        'competition.fixture_lock_kickoff_not_utc',
      );
    });

    test('rejects a non-UTC reference instant', () {
      final result = FixtureLock.at(
        kickoffAt: kickoff,
        nowUtc: DateTime.now(),
      );
      expect(result, isA<Err<FixtureLock>>());
      expect(
        (result as Err<FixtureLock>).error.code,
        'competition.fixture_lock_now_not_utc',
      );
    });
  });
}
