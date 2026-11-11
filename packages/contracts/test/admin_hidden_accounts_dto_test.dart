import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Script 258: the owner's hidden accounts survive the wire unchanged.
void main() {
  test('a hidden account round-trips through JSON', () {
    final HiddenAccountsDto dto = HiddenAccountsDto(
      accounts: [
        HiddenAccountDto(
          user: const UserSummaryDto(
            id: '11111111-1111-4111-8111-111111111111',
            status: 'active',
            email: 'r@t.io',
            displayName: 'مراجع التطبيق',
          ),
          hiddenAt: DateTime.utc(2026, 11, 11, 20),
        ),
      ],
    );

    final Map<String, Object?> json = dto.toJson();
    final HiddenAccountsDto back = HiddenAccountsDto.fromJson(json);

    expect(back, dto);
    final Map<String, Object?> line =
        (json['accounts']! as List<Object?>).single! as Map<String, Object?>;
    expect(line['hidden_at'], '2026-11-11T20:00:00.000Z');
    expect(json['schema_version'], 1);
  });

  test('an empty list is a list', () {
    final HiddenAccountsDto back = HiddenAccountsDto.fromJson(const {
      'accounts': <Object?>[],
    });

    expect(back.accounts, isEmpty);
    expect(back.schemaVersion, 1);
  });
}
