import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';

void main() {
  group('FavoriteTeamsDto', () {
    test('round-trips through JSON in order', () {
      const dto = FavoriteTeamsDto(teamIds: [_b, _a]);

      expect(dto.toJson(), {
        'schema_version': 1,
        'team_ids': [_b, _a],
      });
      expect(FavoriteTeamsDto.fromJson(dto.toJson()), dto);
    });

    test('a missing list reads as empty', () {
      expect(
        FavoriteTeamsDto.fromJson(const {'schema_version': 1}).teamIds,
        isEmpty,
      );
    });

    test('non-string entries are dropped, not guessed', () {
      final dto = FavoriteTeamsDto.fromJson(const {
        'team_ids': [_a, 7, null],
      });

      expect(dto.teamIds, [_a]);
    });
  });
}
