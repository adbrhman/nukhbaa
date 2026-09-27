import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('ReferralSummaryDto round-trips', () {
    const dto = ReferralSummaryDto(
      code: 'ABCDEFGH',
      monthPoints: 3,
      seasonPoints: 7,
      invitedCount: 5,
      pendingCount: 2,
      monthCap: 20,
    );
    final back = ReferralSummaryDto.fromJson(dto.toJson());
    expect(back.code, 'ABCDEFGH');
    expect(back.monthPoints, 3);
    expect(back.seasonPoints, 7);
    expect(back.invitedCount, 5);
    expect(back.pendingCount, 2);
    expect(back.monthCap, 20);
  });

  test('a claim request of the wrong types reads as empty, never throws', () {
    final dto = ReferralClaimRequestDto.fromJson(const {
      'code': 42,
      'install_id': true,
    });
    expect(dto.code, '');
    expect(dto.installId, isNull);
  });

  test('a review request of the wrong types reads as absent', () {
    final dto = ReferralReviewRequestDto.fromJson(const {
      'decision': 1,
      'reason': <String>[],
    });
    expect(dto.decision, isNull);
    expect(dto.reason, isNull);
  });

  test('AdminHeldReferralsDto round-trips its items', () {
    const dto = AdminHeldReferralsDto(
      items: [
        HeldReferralDto(
          inviteeId: 'i',
          inviteeName: 'Badr',
          referrerId: 'r',
          referrerName: 'Ali',
          claimedAt: '2026-10-05T06:00:00.000Z',
          heldAt: '2026-10-10T09:00:00.000Z',
          reasons: ['burst'],
        ),
      ],
    );
    final back = AdminHeldReferralsDto.fromJson(dto.toJson());
    expect(back.items.single.inviteeName, 'Badr');
    expect(back.items.single.reasons, ['burst']);
  });
}
