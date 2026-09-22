import 'package:domain/domain.dart';
import 'package:test/test.dart';

const _a = UserId('aaaaaaaa-0000-0000-0000-000000000001');
const _b = UserId('bbbbbbbb-0000-0000-0000-000000000002');
const _c = UserId('cccccccc-0000-0000-0000-000000000003');
const _d = UserId('dddddddd-0000-0000-0000-000000000004');

void main() {
  group('OvertakeDetector.detect', () {
    test('a member who climbs past another is named', () {
      final passed = OvertakeDetector.detect(
        previous: {_a: 1, _b: 2, _c: 3},
        ordered: const [_a, _c, _b],
      );

      expect(passed, {_b: _c});
    });

    test('the nearest overtaker above is the one named', () {
      final passed = OvertakeDetector.detect(
        previous: {_a: 1, _b: 2, _c: 3, _d: 4},
        ordered: const [_c, _d, _a, _b],
      );

      expect(passed[_a], _d);
      expect(passed[_b], _d);
    });

    test('an unchanged table names nobody', () {
      expect(
        OvertakeDetector.detect(
          previous: {_a: 1, _b: 2},
          ordered: const [_a, _b],
        ),
        isEmpty,
      );
    });

    test('a first look only sets the marks', () {
      expect(
        OvertakeDetector.detect(previous: {}, ordered: const [_b, _a]),
        isEmpty,
      );
    });

    test('a newcomer never counts as an overtaker', () {
      expect(
        OvertakeDetector.detect(
          previous: {_a: 1, _b: 2},
          ordered: const [_c, _a, _b],
        ),
        isEmpty,
      );
    });
  });
}
