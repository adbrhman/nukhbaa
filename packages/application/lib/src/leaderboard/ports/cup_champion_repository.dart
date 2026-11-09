import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read/write port for the champions of the Elite Cup (migrations 0190 and
/// 0204): who won each path of each month, and the optional picture an admin
/// adds to the champion.
///
/// The cup itself (its titles) is written by the scheduler, never here: this
/// port only reads the titles and keeps the pictures.
///
/// General contract: MUST NOT throw; infrastructure failures are
/// [ErrorKind.transient].
abstract interface class CupChampionRepository {
  /// The champions of the cup, newest month first and path 1 to 3 within a
  /// month, at most [limit] rows. A vacant title is not listed.
  Future<Result<List<CupChampion>>> list({required int limit});

  /// Sets or replaces the picture of the champion of [place] in the month
  /// starting [monthStart] (`YYYY-MM-DD`). `Ok(false)` when that path has no
  /// champion (no such month, or a vacant title).
  Future<Result<bool>> setPhoto({
    required String monthStart,
    required int place,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  });

  /// Removes that picture. `Ok(false)` when there was none.
  Future<Result<bool>> removePhoto({
    required String monthStart,
    required int place,
  });

  /// The picture of that champion, or `Ok(null)` when there is none.
  Future<Result<StoredAvatar?>> photo({
    required String monthStart,
    required int place,
  });
}

/// The champion of one path of the Elite Cup of one month, as read back.
final class CupChampion {
  /// Creates the record.
  const CupChampion({
    required this.monthStart,
    required this.place,
    required this.how,
    required this.userId,
    required this.displayName,
    this.photoUpdatedAt,
    this.avatarUpdatedAt,
  });

  /// The first day of the month of the cup, `YYYY-MM-DD`.
  final String monthStart;

  /// The path: 1, 2 or 3 (the place in the league its players came from).
  final int place;

  /// How the title was won: `final`, or `walkover` (the only finalist left).
  final String how;

  /// The champion.
  final UserId userId;

  /// The champion's name as it stands now (a deleted account has none of its
  /// own).
  final String displayName;

  /// When the picture was set, or null without one.
  final DateTime? photoUpdatedAt;

  /// When the champion's own avatar was set, or null without one.
  final DateTime? avatarUpdatedAt;
}
