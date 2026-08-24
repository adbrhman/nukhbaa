import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('DailyDoublePolicy.allowsAnotherDouble', () {
    test('allows the first double of the day', () {
      expect(DailyDoublePolicy.allowsAnotherDouble(0), isTrue);
    });

    test('refuses a second double on the same UTC day', () {
      expect(DailyDoublePolicy.allowsAnotherDouble(1), isFalse);
    });

    test('refuses when the count is already above the cap', () {
      expect(DailyDoublePolicy.allowsAnotherDouble(3), isFalse);
    });
  });
}
