import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Script 263: the people and the close names survive the wire.
void main() {
  test('the people round-trip through JSON', () {
    const dto = PersonLinksDto(
      people: <LinkedPersonDto>[
        LinkedPersonDto(
          mainId: '11111111-1111-4111-8111-111111111111',
          accounts: <LinkedAccountDto>[
            LinkedAccountDto(
              user: UserSummaryDto(
                id: '11111111-1111-4111-8111-111111111111',
                status: 'active',
                displayName: 'عبدالرحمن المغربي',
              ),
              counted: true,
              hidden: false,
            ),
            LinkedAccountDto(
              user: UserSummaryDto(
                id: '22222222-2222-4222-8222-222222222222',
                status: 'active',
                displayName: 'عبد الرحمن المغربي',
              ),
              counted: false,
              hidden: true,
            ),
          ],
        ),
      ],
    );

    expect(PersonLinksDto.fromJson(dto.toJson()), dto);
  });

  test('a new player carries the names like his; absent is none', () {
    final dto = NewPlayerDto(
      user: const UserSummaryDto(id: 'u', status: 'active'),
      joinedAt: DateTime.utc(2026, 11, 12),
      phoneAccounts: 1,
      predictions: 0,
      similarTo: const <String>['عبدالرحمن المغربي'],
    );

    final json = dto.toJson();
    expect(json['similar_to'], <String>['عبدالرحمن المغربي']);
    expect(NewPlayerDto.fromJson(json), dto);
    expect(
      NewPlayerDto.fromJson(json..remove('similar_to')).similarTo,
      isEmpty,
    );
  });

  test('the set request keeps no second when none', () {
    expect(
      const SetPersonRequestDto(otherIds: <String>['a']).toJson(),
      <String, Object?>{
        'other_ids': <String>['a'],
      },
    );
    expect(
      SetPersonRequestDto.fromJson(const {
        'second_id': 'b',
        'other_ids': ['a'],
      }).secondId,
      'b',
    );
  });
}
