import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

// NK300_02
/// One change an admin made, as the owners read it (script 300, migration
/// 0224).
final class AdminActivity {
  /// Creates the line.
  const AdminActivity({
    required this.id,
    required this.actorName,
    required this.method,
    required this.path,
    required this.at,
    this.target,
    this.result,
  });

  /// The row's id.
  final int id;

  /// The admin who made it, by his display name.
  final String actorName;

  /// `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// The request's path, which names the target.
  final String path;

  /// When (UTC).
  final DateTime at;

  /// The player or the match the path names, as it reads now; null when the
  /// path names neither.
  final String? target;

  /// That match's result as it stands now (`2-1`); null for anything else.
  final String? result;
}

/// Port for the admins' activity log (script 300, migration 0224): every
/// write an admin made on the admin paths, kept for the owners to check.
/// Append-only. MUST NOT throw; an infrastructure failure is transient.
abstract interface class AdminActivityLog {
  /// Keeps that [actor] made the request [method] [path], answered
  /// [status].
  Future<Result<void>> record({
    required UserId actor,
    required String method,
    required String path,
    required int status,
  });

  /// The latest [limit] changes, the newest first.
  Future<Result<List<AdminActivity>>> latest({int limit = 200});
}
