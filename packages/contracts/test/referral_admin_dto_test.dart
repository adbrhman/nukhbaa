import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('AdminReferralOverviewDto round-trips', () {
    const dto = AdminReferralOverviewDto(
      enabled: true,
      stateCounts: {'paid': 3, 'held': 1},
      referrers: [
        ReferrerTotalsDto(
          referrerId: 'r',
          referrerName: 'Ali',
          invited: 4,
          paid: 3,
          pending: 0,
          held: 1,
          refused: 0,
          monthPoints: 3,
        ),
      ],
      invitations: [
        ReferralInvitationDto(
          inviteeId: 'i',
          inviteeName: 'Badr',
          inviteeStatus: 'suspended',
          referrerId: 'r',
          referrerName: 'Ali',
          claimedAt: '2026-10-01T07:05:00.000Z',
          state: 'revoked',
          holdReasons: [],
          revokeReason: 'inactive_7_days',
        ),
      ],
    );
    final back = AdminReferralOverviewDto.fromJson(dto.toJson());
    expect(back.enabled, isTrue);
    expect(back.stateCounts, {'paid': 3, 'held': 1});
    expect(back.referrers.single.monthPoints, 3);
    expect(back.invitations.single.revokeReason, 'inactive_7_days');
  });

  test('the switch reads only a real boolean', () {
    expect(ReferralSwitchDto.enabledOf(const {'enabled': false}), isFalse);
    expect(ReferralSwitchDto.enabledOf(const {'enabled': 'no'}), isNull);
    expect(ReferralSwitchDto.enabledOf(const {}), isNull);
  });
}
