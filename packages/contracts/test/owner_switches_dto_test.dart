import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

// NK289_12
/// Script 289: the owners' switches survive the wire unchanged.
void main() {
  test('a switch and its last change round-trip through JSON', () {
    final OwnerSwitchesDto dto = OwnerSwitchesDto(
      switches: [
        OwnerSwitchDto(
          key: 'crowning',
          isOn: false,
          reason: 'مراجعة نقاط الشهر',
          changedBy: OwnerSwitchDto.byYou,
          changedAt: DateTime.utc(2026, 11, 30, 18),
        ),
      ],
    );

    final Map<String, Object?> json = dto.toJson();
    final OwnerSwitchesDto back = OwnerSwitchesDto.fromJson(json);

    expect(back, dto);
    final Map<String, Object?> line =
        (json['switches']! as List<Object?>).single! as Map<String, Object?>;
    expect(line['is_on'], isFalse);
    expect(line['changed_by'], 'you');
    expect(line['changed_at'], '2026-11-30T18:00:00.000Z');
    expect(json['schema_version'], 1);
  });

  test('a switch never changed has no reason and no author', () {
    final OwnerSwitchDto back = OwnerSwitchDto.fromJson(const {
      'key': 'crowning',
      'is_on': true,
      'reason': null,
      'changed_by': null,
      'changed_at': '2026-11-20T00:00:00.000Z',
    });

    expect(back.isOn, isTrue);
    expect(back.reason, isNull);
    expect(back.changedBy, isNull);
  });
}
