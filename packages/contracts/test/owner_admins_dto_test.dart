import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

// NK294_13
/// Script 294: the owners' page of admins survives the wire unchanged.
void main() {
  test('the admins and the log round-trip through JSON', () {
    final OwnerAdminsDto dto = OwnerAdminsDto(
      admins: const [
        OwnerAdminDto(
          id: 'u-1',
          displayName: 'المالك',
          active: true,
          isOwner: true,
          email: 'o@t.io',
        ),
      ],
      changes: [
        RoleChangeDto(
          userName: 'خالد',
          action: 'revoke',
          reason: 'سوء استخدام',
          at: DateTime.utc(2026, 11, 20, 12),
          sessionsEnded: 2,
        ),
      ],
    );

    final Map<String, Object?> json = dto.toJson();

    expect(OwnerAdminsDto.fromJson(json), dto);
    final Map<String, Object?> line =
        (json['admins']! as List<Object?>).single! as Map<String, Object?>;
    expect(line['is_owner'], isTrue);
  });
}
