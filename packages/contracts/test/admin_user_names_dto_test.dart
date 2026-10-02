import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('AdminRenameUserRequestDto', () {
    test('round-trips with snake_case keys', () {
      const request = AdminRenameUserRequestDto(
        displayName: 'أحمد الثاني',
        reason: 'اسم مكرر',
      );

      final json = request.toJson();

      expect(json['display_name'], 'أحمد الثاني');
      expect(AdminRenameUserRequestDto.fromJson(json), request);
    });

    test('a missing or non-string field parses as null', () {
      final parsed = AdminRenameUserRequestDto.fromJson(<String, Object?>{
        'display_name': 7,
      });

      expect(parsed.displayName, isNull);
      expect(parsed.reason, isNull);
      expect(parsed.schemaVersion, 1);
    });
  });

  group('DuplicateNamesDto', () {
    const a = UserSummaryDto(
      id: '11111111-1111-4111-8111-111111111111',
      email: 'a@t.io',
      displayName: 'أحمد',
      status: 'active',
    );
    const b = UserSummaryDto(
      id: '22222222-2222-4222-8222-222222222222',
      email: 'b@t.io',
      displayName: 'احمد',
      status: 'suspended',
    );

    test('round-trips its groups in order', () {
      const dto = DuplicateNamesDto(
        groups: [
          [a, b],
        ],
      );

      final parsed = DuplicateNamesDto.fromJson(dto.toJson());

      expect(parsed, dto);
      expect(parsed.groups.single.last.status, 'suspended');
    });

    test('no groups is an empty list', () {
      final parsed = DuplicateNamesDto.fromJson(<String, Object?>{
        'schema_version': 1,
        'groups': <Object?>[],
      });

      expect(parsed.groups, isEmpty);
    });
  });
}
