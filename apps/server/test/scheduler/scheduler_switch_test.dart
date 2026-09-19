import 'package:server/scheduler/scheduler_switch.dart';
import 'package:test/test.dart';

void main() {
  group('schedulersEnabled', () {
    test('is on when the variable is absent (deployed default)', () {
      expect(schedulersEnabled(<String, String>{}), isTrue);
    });

    test('is on for an empty or any non-off value', () {
      for (final value in <String>['', 'on', 'no', 'false', 'shadow']) {
        expect(
          schedulersEnabled(<String, String>{schedulersEnvKey: value}),
          isTrue,
          reason: 'value "$value"',
        );
      }
    });

    test('is off only for an explicit off, ignoring case and spaces', () {
      for (final value in <String>['off', 'OFF', ' Off ']) {
        expect(
          schedulersEnabled(<String, String>{schedulersEnvKey: value}),
          isFalse,
          reason: 'value "$value"',
        );
      }
    });
  });
}
