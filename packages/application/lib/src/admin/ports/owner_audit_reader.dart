import 'package:shared/shared.dart';

// NK341_01
/// One action an owner took, as the owners' own log reads it (script 341,
/// plan 339 to 348).
///
/// It comes from one of two tables, so a line is told apart by [source] and
/// [id] together: their ids are counted apart.
final class OwnerAuditLine {
  /// Creates the line.
  const OwnerAuditLine({
    required this.source,
    required this.id,
    required this.actorName,
    required this.method,
    required this.path,
    required this.at,
    this.target,
    this.result,
  });

  /// A request to `/owner` (`admin.owner_audit_log`).
  static const String sourceOwner = 'owner';

  /// A change made inside the admins' tools by an owner seat
  /// (`admin.admin_activity_log`).
  static const String sourceAdmin = 'admin';

  /// Which table the line came from: [sourceOwner] or [sourceAdmin].
  final String source;

  /// The row's id inside its own table.
  final int id;

  /// The owner who acted, by his display name.
  final String actorName;

  /// `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// The request's path.
  final String path;

  /// When (UTC).
  final DateTime at;

  /// The player or the match the path names, as it reads now; null for an
  /// owner-page line and when the path names neither.
  final String? target;

  /// That match's result as it stands now (`2-1`); null for anything else.
  final String? result;
}

/// Read port for the owners' own audit log (plan 339 to 348): what the owner
/// seats did, from `admin.owner_audit_log` and from the owner seats' rows of
/// `admin.admin_activity_log`, newest first. Apart from the write port
/// [OwnerAuditLog], which only appends.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class OwnerAuditReader {
  /// The latest [limit] actions of the owner seats, the newest first.
  Future<Result<List<OwnerAuditLine>>> latest({int limit = 200});
}
