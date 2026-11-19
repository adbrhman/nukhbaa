import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the owners' own audit log (script 287, migration 0219,
/// decision Q01): every change an owner seat makes under `/owner`, kept
/// apart from the admins' log (`admin.audit_log`), which no owner action
/// enters. Append-only.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class OwnerAuditLog {
  /// Keeps that [actor] made the request [method] [path], answered
  /// [status].
  Future<Result<void>> record({
    required UserId actor,
    required String method,
    required String path,
    required int status,
  });
}
