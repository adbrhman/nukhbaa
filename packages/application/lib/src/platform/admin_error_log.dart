/// Use-case: the admin dashboard's error log (migrations 0087, 0088).
library;

import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/platform/ports/error_log_admin_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One page of the error log: the counts of every list, the errors of the
/// list asked for, and the admins an error can be assigned to.
final class AdminErrorList {
  /// Creates the page.
  const AdminErrorList({
    required this.counts,
    required this.errors,
    required this.admins,
  });

  /// How many errors each list holds.
  final ErrorListCounts counts;

  /// The errors asked for, last seen first.
  final List<ErrorGroupView> errors;

  /// The admins an error can be assigned to.
  final List<AdminRef> admins;
}

/// Reads and changes the error log, for admins only.
///
/// A change -- status, severity, assignee, notes -- is written first and
/// then recorded in the audit trail ([AuditAction.errorUpdated]) with the
/// old and new values; a change that changes nothing writes nothing.
/// Marking an error `fixed` is what lets the log reopen it when a build
/// that never had it reports it again (`ops.record_error`).
///
/// Never throws; returns a typed [Result].
final class AdminErrorLog {
  /// Creates the use-case over its collaborators.
  const AdminErrorLog({
    required ErrorLogAdminRepository errors,
    required AuditRecorder auditRecorder,
    required Clock clock,
  }) : _errors = errors,
       _audit = auditRecorder,
       _clock = clock;

  final ErrorLogAdminRepository _errors;
  final AuditRecorder _audit;
  final Clock _clock;

  /// The statuses an error can have.
  static const List<String> statuses = <String>[
    'new',
    'in_progress',
    'fixed',
    'verified',
    'ignored',
  ];

  /// The severities an error can have.
  static const List<String> severities = <String>[
    'critical',
    'high',
    'medium',
    'low',
  ];

  /// The most errors one list shows.
  static const int maxList = 200;

  /// The longest notes kept.
  static const int maxNotes = 4000;

  static final RegExp _problemCode = RegExp(r'^[A-HJ-NP-Z2-9]{4}$');
  static final RegExp _build = RegExp(r'^[0-9A-Za-z._-]{1,40}$');

  /// The errors of [kind] (or of [problemCode], in every list), with the
  /// counts and the admins.
  Future<Result<AdminErrorList>> list({
    required AuthenticatedUser principal,
    required ErrorListKind kind,
    String? source,
    String? build,
    String? problemCode,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final String? code = problemCode?.trim().toUpperCase();
    if (code != null && code.isNotEmpty && !_problemCode.hasMatch(code)) {
      return const Result.err(
        AppError.validation(
          'errors.invalid_problem_code',
          'رمز المشكلة 4 أحرف أو أرقام',
        ),
      );
    }
    final String? onlySource = source?.trim();
    if (onlySource != null &&
        onlySource.isNotEmpty &&
        !const {'server', 'android', 'ios', 'web'}.contains(onlySource)) {
      return const Result.err(
        AppError.validation('errors.invalid_source', 'مصدر غير معروف'),
      );
    }
    final String? onlyBuild = build?.trim();
    if (onlyBuild != null &&
        onlyBuild.isNotEmpty &&
        !_build.hasMatch(onlyBuild)) {
      return const Result.err(
        AppError.validation('errors.invalid_build', 'رقم إصدار غير صالح'),
      );
    }

    final counts = await _errors.counts();
    if (counts is Err<ErrorListCounts>) {
      return Result.err(counts.error);
    }
    final rows = await _errors.list(
      kind: kind,
      limit: maxList,
      source: _blankToNull(onlySource),
      build: _blankToNull(onlyBuild),
      problemCode: _blankToNull(code),
    );
    if (rows is Err<List<ErrorGroupView>>) {
      return Result.err(rows.error);
    }
    final admins = await _errors.admins();
    if (admins is Err<List<AdminRef>>) {
      return Result.err(admins.error);
    }
    return Result.ok(
      AdminErrorList(
        counts: (counts as Ok<ErrorListCounts>).value,
        errors: (rows as Ok<List<ErrorGroupView>>).value,
        admins: (admins as Ok<List<AdminRef>>).value,
      ),
    );
  }

  /// The error [id] in full.
  Future<Result<ErrorGroupDetail>> detail({
    required AuthenticatedUser principal,
    required int id,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _detail(id);
  }

  /// Changes the error [id]. A null argument keeps its value; an empty
  /// [assigneeId] removes the assignee; empty [notes] clear them.
  Future<Result<ErrorGroupDetail>> update({
    required AuthenticatedUser principal,
    required int id,
    String? status,
    String? severity,
    String? assigneeId,
    String? notes,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (status != null && !statuses.contains(status)) {
      return const Result.err(
        AppError.validation('errors.invalid_status', 'حالة غير معروفة'),
      );
    }
    if (severity != null && !severities.contains(severity)) {
      return const Result.err(
        AppError.validation('errors.invalid_severity', 'خطورة غير معروفة'),
      );
    }
    final String? trimmedNotes = notes?.trim();
    if (trimmedNotes != null && trimmedNotes.length > maxNotes) {
      return const Result.err(
        AppError.validation(
          'errors.notes_too_long',
          'الملاحظات طويلة جدًا (الحد الأقصى $maxNotes حرف)',
        ),
      );
    }

    final before = await _detail(id);
    if (before is Err<ErrorGroupDetail>) {
      return before;
    }
    final ErrorGroupView old = (before as Ok<ErrorGroupDetail>).value.group;

    final String? assignee = assigneeId?.trim();
    final bool clearAssignee = assignee != null && assignee.isEmpty;
    String? assigneeName;
    if (assignee != null && assignee.isNotEmpty) {
      final admins = await _errors.admins();
      if (admins is Err<List<AdminRef>>) {
        return Result.err(admins.error);
      }
      for (final AdminRef admin in (admins as Ok<List<AdminRef>>).value) {
        if (admin.id == assignee) {
          assigneeName = admin.displayName;
        }
      }
      if (assigneeName == null) {
        return const Result.err(
          AppError.validation(
            'errors.assignee_not_admin',
            'المسؤول يجب أن يكون مشرفًا',
          ),
        );
      }
    }

    final List<String> changes = <String>[
      if (status != null && status != old.status)
        'status: ${old.status} -> $status',
      if (severity != null && severity != old.severity)
        'severity: ${old.severity} -> $severity',
      if (clearAssignee && old.assigneeId != null)
        'assignee: ${old.assigneeName ?? old.assigneeId} -> -',
      if (assigneeName != null && assignee != old.assigneeId)
        'assignee: ${old.assigneeName ?? '-'} -> $assigneeName',
      if (trimmedNotes != null && trimmedNotes != (old.adminNotes ?? ''))
        'notes changed',
    ];
    if (changes.isEmpty) {
      return before;
    }

    final written = await _errors.update(
      id,
      at: _clock.nowUtc(),
      status: status,
      severity: severity,
      assigneeId: assigneeName == null ? null : assignee,
      clearAssignee: clearAssignee,
      setNotes: trimmedNotes != null,
      notes: trimmedNotes == null || trimmedNotes.isEmpty ? null : trimmedNotes,
    );
    if (written is Err<bool>) {
      return Result.err(written.error);
    }
    if (!(written as Ok<bool>).value) {
      return _notFound;
    }

    final String reason = changes.join('; ');
    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.errorUpdated,
      targetRef: 'error:$id (${old.problemCode})',
      reason: reason.length > AuditEntry.maxReasonLength
          ? reason.substring(0, AuditEntry.maxReasonLength)
          : reason,
    );
    if (audit is Err<AuditEntry>) {
      return Result.err(audit.error);
    }
    return _detail(id);
  }

  Future<Result<ErrorGroupDetail>> _detail(int id) async {
    final found = await _errors.detail(id);
    if (found is Err<ErrorGroupDetail?>) {
      return Result.err(found.error);
    }
    final ErrorGroupDetail? detail = (found as Ok<ErrorGroupDetail?>).value;
    return detail == null ? _notFound : Result.ok(detail);
  }

  static const Result<ErrorGroupDetail> _notFound = Result.err(
    AppError.invariant('errors.not_found', 'الخطأ غير موجود في السجل'),
  );

  static String? _blankToNull(String? value) =>
      value == null || value.isEmpty ? null : value;
}
