/// Use-cases: the champions of the Elite Cup and their pictures
/// (migrations 0190 and 0204).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:application/src/leaderboard/ports/cup_champion_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The champions of the Elite Cup, for every signed-in player, and the
/// picture an admin adds to a champion (decided by the owner on 2026-11-09:
/// the cup's titles are decided by the server, the admin only adds the
/// picture, and a champion without one shows his avatar, then initials).
///
/// Reading is for any signed-in player, like the month's champions; adding or
/// removing a picture is for an admin only. A picture follows the avatar
/// rules (`User.validateAvatar`: 512 KB, JPEG / PNG / WEBP).
///
/// Never throws; returns typed [Result]s.
final class CupChampions {
  /// Creates the use-cases over their store.
  const CupChampions({
    required CupChampionRepository champions,
    required Clock clock,
  }) : _champions = champions,
       _clock = clock;

  /// The most champions one call lists.
  static const int maxLimit = 60;

  final CupChampionRepository _champions;
  final Clock _clock;

  /// The champions, newest month first, for any signed-in player.
  Future<Result<List<CupChampion>>> list({
    required AuthenticatedUser principal,
    int limit = maxLimit,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final int bounded = limit < 1 ? 1 : (limit > maxLimit ? maxLimit : limit);
    return _champions.list(limit: bounded);
  }

  /// The picture of one champion, or `Ok(null)` when there is none.
  Future<Result<StoredAvatar?>> photo({
    required AuthenticatedUser principal,
    required String monthStart,
    required String place,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final target = _target(monthStart, place);
    if (target is Err<_Target>) {
      return Result.err(target.error);
    }
    final t = (target as Ok<_Target>).value;
    return _champions.photo(monthStart: t.monthStart, place: t.place);
  }

  /// Stores [bytes] as the picture of the champion of that path; answers the
  /// champions as they stand after the change.
  Future<Result<List<CupChampion>>> setPhoto({
    required AuthenticatedUser principal,
    required String monthStart,
    required String place,
    required List<int> bytes,
    required String mime,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final target = _target(monthStart, place);
    if (target is Err<_Target>) {
      return Result.err(target.error);
    }
    final validated = User.validateAvatar(bytes.length, mime);
    if (validated is Err<void>) {
      return Result.err(validated.error);
    }
    final t = (target as Ok<_Target>).value;
    final stored = await _champions.setPhoto(
      monthStart: t.monthStart,
      place: t.place,
      bytes: bytes,
      mime: mime,
      now: _clock.nowUtc(),
    );
    if (stored is Err<bool>) {
      return Result.err(stored.error);
    }
    if (!(stored as Ok<bool>).value) {
      return const Result.err(_notFound);
    }
    return _champions.list(limit: maxLimit);
  }

  /// Removes the picture of the champion of that path; answers the champions
  /// as they stand after the change.
  Future<Result<List<CupChampion>>> removePhoto({
    required AuthenticatedUser principal,
    required String monthStart,
    required String place,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final target = _target(monthStart, place);
    if (target is Err<_Target>) {
      return Result.err(target.error);
    }
    final t = (target as Ok<_Target>).value;
    final removed = await _champions.removePhoto(
      monthStart: t.monthStart,
      place: t.place,
    );
    if (removed is Err<bool>) {
      return Result.err(removed.error);
    }
    return _champions.list(limit: maxLimit);
  }

  static const AppError _notFound = AppError.invariant(
    'cup.champion_not_found',
    'لا بطل لهذا المسار في هذا الشهر',
  );

  static final RegExp _monthPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$');

  static Result<_Target> _target(String monthStart, String place) {
    final int? path = int.tryParse(place);
    if (!_monthPattern.hasMatch(monthStart) ||
        path == null ||
        path < 1 ||
        path > 3) {
      return const Result.err(
        AppError.validation(
          'cup.target_invalid',
          'شهر الكأس أو المسار غير صالح',
        ),
      );
    }
    return Result.ok(_Target(monthStart, path));
  }
}

final class _Target {
  const _Target(this.monthStart, this.place);

  final String monthStart;
  final int place;
}
