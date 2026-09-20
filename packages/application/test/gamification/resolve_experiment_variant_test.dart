import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = UserId('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');
const _flag = 'daily_challenge_copy';
const _arms = <ExperimentArm>[
  ExperimentArm(name: 'control', weight: 50),
  ExperimentArm(name: 'treatment', weight: 50),
];

const _transient = AppError(
  kind: ErrorKind.transient,
  code: 'db.unavailable',
  message: 'no',
);

/// Records what the use-case asked for, so a test can assert that a stopped
/// experiment wrote nothing.
final class _FakeExperiments implements ExperimentRepository {
  _FakeExperiments({
    this.enabled = const Result<bool>.ok(true),
    this.assignment = const Result<String?>.ok(null),
    this.stored,
  });

  final Result<bool> enabled;
  final Result<String?> assignment;
  final Result<String>? stored;

  final List<String> flagReads = <String>[];
  final List<String> assignmentReads = <String>[];
  final List<String> writes = <String>[];

  @override
  Future<Result<bool>> isFlagEnabled(String flagKey) async {
    flagReads.add(flagKey);
    return enabled;
  }

  @override
  Future<Result<String?>> readAssignment({
    required UserId userId,
    required String flagKey,
  }) async {
    assignmentReads.add(flagKey);
    return assignment;
  }

  @override
  Future<Result<String>> assign({
    required UserId userId,
    required String flagKey,
    required String variant,
  }) async {
    writes.add(variant);
    return stored ?? Result<String>.ok(variant);
  }
}

void main() {
  group('ResolveExperimentVariant', () {
    test('a flag that is off answers control and assigns nobody', () async {
      final experiments = _FakeExperiments(
        enabled: const Result<bool>.ok(false),
      );

      final String variant = await ResolveExperimentVariant(
        experiments: experiments,
      ).call(userId: _user, flagKey: _flag, arms: _arms);

      expect(variant, 'control');
      expect(experiments.writes, isEmpty);
      // The assignment is never even read: a stopped experiment measures
      // no one.
      expect(experiments.assignmentReads, isEmpty);
    });

    test('a stored variant is returned untouched', () async {
      final experiments = _FakeExperiments(
        assignment: const Result<String?>.ok('treatment'),
      );

      final String variant = await ResolveExperimentVariant(
        experiments: experiments,
      ).call(userId: _user, flagKey: _flag, arms: _arms);

      expect(variant, 'treatment');
      expect(experiments.writes, isEmpty);
    });

    test('a variant no longer in the arms is still returned', () async {
      final experiments = _FakeExperiments(
        assignment: const Result<String?>.ok('retired_arm'),
      );

      final String variant = await ResolveExperimentVariant(
        experiments: experiments,
      ).call(userId: _user, flagKey: _flag, arms: _arms);

      expect(variant, 'retired_arm');
      expect(experiments.writes, isEmpty);
    });

    test('first exposure allocates, stores and returns the same arm', () async {
      final experiments = _FakeExperiments();
      final String expected = VariantAllocator.allocate(
        userId: _user.value,
        flagKey: _flag,
        arms: _arms,
      );

      final String variant = await ResolveExperimentVariant(
        experiments: experiments,
      ).call(userId: _user, flagKey: _flag, arms: _arms);

      expect(experiments.writes, <String>[expected]);
      expect(variant, expected);
    });

    test('the loser of a race gets the winner\'s arm', () async {
      final experiments = _FakeExperiments(
        stored: const Result<String>.ok('treatment'),
      );
      final String drawn = VariantAllocator.allocate(
        userId: _user.value,
        flagKey: _flag,
        arms: _arms,
      );

      final String variant = await ResolveExperimentVariant(
        experiments: experiments,
      ).call(userId: _user, flagKey: _flag, arms: _arms);

      expect(experiments.writes, <String>[drawn]);
      expect(variant, 'treatment');
    });

    test('a failed flag read answers control', () async {
      final experiments = _FakeExperiments(
        enabled: const Result<bool>.err(_transient),
      );

      final String variant = await ResolveExperimentVariant(
        experiments: experiments,
      ).call(userId: _user, flagKey: _flag, arms: _arms);

      expect(variant, 'control');
      expect(experiments.writes, isEmpty);
    });

    test('a failed write answers control and keeps nothing', () async {
      final experiments = _FakeExperiments(
        stored: const Result<String>.err(_transient),
      );

      final String variant = await ResolveExperimentVariant(
        experiments: experiments,
      ).call(userId: _user, flagKey: _flag, arms: _arms);

      expect(variant, 'control');
    });
  });
}
