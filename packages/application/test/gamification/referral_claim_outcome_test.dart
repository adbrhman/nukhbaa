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

  test('duplicate_account (migration 0109) is a known outcome', () {
    expect(
      ReferralClaimOutcome.fromWire('duplicate_account'),
      ReferralClaimOutcome.duplicateAccount,
    );
  });
}
