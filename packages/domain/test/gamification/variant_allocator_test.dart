import 'package:domain/domain.dart';
import 'package:test/test.dart';

const _arms = <ExperimentArm>[
  ExperimentArm(name: 'control', weight: 50),
  ExperimentArm(name: 'treatment', weight: 50),
];

/// A stable population of synthetic user ids, so a distribution assertion is
/// about the hash and not about whichever ids a run happened to invent.
List<String> _population(int count) => <String>[
  for (var i = 0; i < count; i++)
    '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
];

void main() {
  group('VariantAllocator.allocate', () {
    test('the same user and flag always land in the same arm', () {
      for (final String user in _population(50)) {
        final String first = VariantAllocator.allocate(
          userId: user,
          flagKey: 'daily_challenge_copy',
          arms: _arms,
        );
        final String second = VariantAllocator.allocate(
          userId: user,
          flagKey: 'daily_challenge_copy',
          arms: _arms,
        );
        expect(second, first);
      }
    });

    test('a 50/50 split actually splits', () {
      final List<String> users = _population(1000);
      final int treatment = users
          .where(
            (user) =>
                VariantAllocator.allocate(
                  userId: user,
                  flagKey: 'daily_challenge_copy',
                  arms: _arms,
                ) ==
                'treatment',
          )
          .length;

      // A constant allocator would score 0 or 1000 here.
      expect(treatment, greaterThan(400));
      expect(treatment, lessThan(600));
    });

    test('weights are honoured', () {
      const skewed = <ExperimentArm>[
        ExperimentArm(name: 'control', weight: 90),
        ExperimentArm(name: 'treatment', weight: 10),
      ];
      final List<String> users = _population(1000);
      final int treatment = users
          .where(
            (user) =>
                VariantAllocator.allocate(
                  userId: user,
                  flagKey: 'reminder_lead_time',
                  arms: skewed,
                ) ==
                'treatment',
          )
          .length;

      expect(treatment, greaterThan(50));
      expect(treatment, lessThan(160));
    });

    test('a different flag re-buckets the population', () {
      final List<String> users = _population(200);
      var moved = 0;
      for (final String user in users) {
        final String a = VariantAllocator.allocate(
          userId: user,
          flagKey: 'flag_a',
          arms: _arms,
        );
        final String b = VariantAllocator.allocate(
          userId: user,
          flagKey: 'flag_b',
          arms: _arms,
        );
        if (a != b) {
          moved += 1;
        }
      }

      // Two independent experiments must not hand the same users the same
      // arm, or every result is confounded with every other result.
      expect(moved, greaterThan(50));
    });

    test('an arm with no weight is never drawn', () {
      const withDead = <ExperimentArm>[
        ExperimentArm(name: 'control', weight: 1),
        ExperimentArm(name: 'retired', weight: 0),
      ];
      for (final String user in _population(100)) {
        expect(
          VariantAllocator.allocate(
            userId: user,
            flagKey: 'flag',
            arms: withDead,
          ),
          'control',
        );
      }
    });

    test('nothing to split answers control', () {
      expect(
        VariantAllocator.allocate(
          userId: 'u',
          flagKey: 'flag',
          arms: const <ExperimentArm>[],
        ),
        'control',
      );
    });
  });
}
