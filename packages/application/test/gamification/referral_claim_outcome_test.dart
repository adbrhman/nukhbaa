import 'package:application/application.dart';
import 'package:test/test.dart';

/// The two refusals of migration 0086 travel by their database names.
void main() {
  test('app_required and same_device are known outcomes', () {
    expect(
      ReferralClaimOutcome.fromWire('app_required'),
      ReferralClaimOutcome.appRequired,
    );
    expect(
      ReferralClaimOutcome.fromWire('same_device'),
      ReferralClaimOutcome.sameDevice,
    );
  });
}
