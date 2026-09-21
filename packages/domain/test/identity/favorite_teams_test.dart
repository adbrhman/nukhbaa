import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';
const _d = '44444444-4444-4444-8444-444444444444';

void main() {
  group('FavoriteTeams.tryCreate', () {
    test('keeps up to three teams in the order given', () {
      final result = FavoriteTeams.tryCreate(const [
        TeamRef(_c),
        TeamRef(_a),
        TeamRef(_b),
      ]);

      expect((result as Ok<FavoriteTeams>).value.teams, const [
        TeamRef(_c),
        TeamRef(_a),
        TeamRef(_b),
      ]);
    });

    test('drops a repeated team before counting', () {
      final result = FavoriteTeams.tryCreate(const [
        TeamRef(_a),
        TeamRef(_a),
        TeamRef(_b),
        TeamRef(_c),
      ]);

      expect((result as Ok<FavoriteTeams>).value.teams, hasLength(3));
    });

    test('refuses a fourth team', () {
      final result = FavoriteTeams.tryCreate(const [
        TeamRef(_a),
        TeamRef(_b),
        TeamRef(_c),
        TeamRef(_d),
      ]);

      final error = (result as Err<FavoriteTeams>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'identity.favorite_teams_too_many');
    });

    test('an empty list is none', () {
      final result = FavoriteTeams.tryCreate(const []);

      expect((result as Ok<FavoriteTeams>).value, FavoriteTeams.none);
    });
  });
}
