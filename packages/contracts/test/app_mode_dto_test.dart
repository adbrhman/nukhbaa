import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

// NK292_15
/// Script 292: the app's mode survives the wire unchanged.
void main() {
  test('the mode and its last change round-trip through JSON', () {
    final AppModeDto dto = AppModeDto(
      mode: AppModeDto.readOnly,
      reason: 'خطأ في النقاط',
      changedBy: OwnerSwitchDto.byYou,
      changedAt: DateTime.utc(2026, 11, 20, 12),
    );

    final Map<String, Object?> json = dto.toJson();

    expect(AppModeDto.fromJson(json), dto);
    expect(json['mode'], 'read_only');
    expect(json['changed_at'], '2026-11-20T12:00:00.000Z');
  });
}
