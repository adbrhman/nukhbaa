import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';
const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';
const _d = '44444444-4444-4444-8444-444444444444';

/// In-memory [FavoriteTeamRepository]: one set per user, and a count of
/// writes so a rejected request is visible as "never reached the store".
final class _InMemoryFavorites implements FavoriteTeamRepository {
  final Map<String, FavoriteTeams> byUser = {};
  int writes = 0;

  @override
  Future<Result<FavoriteTeams>> favoritesOf(UserId userId) async =>
      Result.ok(byUser[userId.value] ?? FavoriteTeams.none);

  @override
  Future<Result<FavoriteTeams>> replace(
    UserId userId,
    FavoriteTeams teams,
  ) async {
    writes += 1;
    byUser[userId.value] = teams;
    return Result.ok(teams);
  }
}

AuthenticatedUser _principal() => const AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
  email: 'a@example.com',
  displayName: 'Human',
);

void main() {
  group('SetMyFavoriteTeams then GetMyFavoriteTeams', () {
    test('stores the set against the caller and reads it back', () async {
      final store = _InMemoryFavorites();
      final setTeams = SetMyFavoriteTeams(favorites: store);
      final getTeams = GetMyFavoriteTeams(favorites: store);

      final stored = await setTeams(
        principal: _principal(),
        teams: const [TeamRef(_b), TeamRef(_a)],
      );
      final read = await getTeams(principal: _principal());

      final storedTeams = (stored as Ok<FavoriteTeams>).value;
      expect(storedTeams.teams, const [TeamRef(_b), TeamRef(_a)]);
      expect((read as Ok<FavoriteTeams>).value, storedTeams);
    });

    test('a caller who never chose reads none', () async {
      final getTeams = GetMyFavoriteTeams(favorites: _InMemoryFavorites());

      final read = await getTeams(principal: _principal());

      expect((read as Ok<FavoriteTeams>).value, FavoriteTeams.none);
    });

    test('an empty list clears the set', () async {
      final store = _InMemoryFavorites();
      final setTeams = SetMyFavoriteTeams(favorites: store);
      await setTeams(principal: _principal(), teams: const [TeamRef(_a)]);

      await setTeams(principal: _principal(), teams: const []);
      final read = await GetMyFavoriteTeams(favorites: store)(
        principal: _principal(),
      );

      expect((read as Ok<FavoriteTeams>).value, FavoriteTeams.none);
    });

    test('a fourth team is refused before anything is written', () async {
      final store = _InMemoryFavorites();
      final setTeams = SetMyFavoriteTeams(favorites: store);

      final result = await setTeams(
        principal: _principal(),
        teams: const [TeamRef(_a), TeamRef(_b), TeamRef(_c), TeamRef(_d)],
      );

      expect(
        (result as Err<FavoriteTeams>).error.code,
        'identity.favorite_teams_too_many',
      );
      expect(store.writes, 0);
    });
  });
}
