import 'package:shared/shared.dart';

/// The lists of the admin error log (migration 0087).
enum ErrorListKind {
  /// Every error, whatever its status.
  all('all'),

  /// Errors no admin has looked at yet (status `new`).
  fresh('new'),

  /// Open errors that keep coming: seen [ErrorLogAdminRepository.recurringFrom]
  /// times or more, or back after a fix.
  recurring('recurring'),

  /// Open errors marked critical.
  critical('critical');

  const ErrorListKind(this.wire);

  /// The token in `GET /admin/errors?list=`.
  final String wire;

  /// The kind for [raw], or null when it is not one.
  static ErrorListKind? fromWire(String? raw) {
    for (final kind in ErrorListKind.values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

/// How many errors each list holds.
final class ErrorListCounts {
  /// Creates the counts.
  const ErrorListCounts({
    required this.all,
    required this.fresh,
    required this.recurring,
    required this.critical,
  });

  /// Every error.
  final int all;

  /// Status `new`.
  final int fresh;

  /// Open and recurring.
  final int recurring;

  /// Open and critical.
  final int critical;
}

/// One error of the error log, as the admin sees it in a list or on its
/// page.
final class ErrorGroupView {
  /// Creates the view.
  const ErrorGroupView({
    required this.id,
    required this.problemCode,
    required this.source,
    required this.errorType,
    required this.message,
    required this.severity,
    required this.status,
    required this.firstBuild,
    required this.lastBuild,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.occurrences,
    required this.usersAffected,
    required this.reopenedCount,
    this.errorCode,
    this.locationFile,
    this.locationLine,
    this.locationSymbol,
    this.assigneeId,
    this.assigneeName,
    this.adminNotes,
  });

  /// The row id.
  final int id;

  /// The 4 characters a player reads out.
  final String problemCode;

  /// `server`, `android`, `ios` or `web`.
  final String source;

  /// The error's runtime type.
  final String errorType;

  /// The stable `AppError` code, when there is one.
  final String? errorCode;

  /// What went wrong, redacted.
  final String message;

  /// Where it happened.
  final String? locationFile;

  /// The line of [locationFile].
  final int? locationLine;

  /// The member running at [locationFile].
  final String? locationSymbol;

  /// `critical`, `high`, `medium` or `low`.
  final String severity;

  /// `new`, `in_progress`, `fixed`, `verified` or `ignored`.
  final String status;

  /// The admin in charge, if any.
  final String? assigneeId;

  /// Their display name.
  final String? assigneeName;

  /// The admins' notes.
  final String? adminNotes;

  /// The first build that hit it.
  final String firstBuild;

  /// The latest build that hit it.
  final String lastBuild;

  /// When it was first seen.
  final DateTime firstSeenAt;

  /// When it was last seen.
  final DateTime lastSeenAt;

  /// Times it happened.
  final int occurrences;

  /// Distinct signed-in players it hit.
  final int usersAffected;

  /// Times it came back after a fix.
  final int reopenedCount;
}

/// One of the last occurrences of an error, in full.
final class ErrorSampleView {
  /// Creates the view.
  const ErrorSampleView({
    required this.occurredAt,
    required this.build,
    required this.message,
    this.requestId,
    this.userId,
    this.userName,
    this.route,
    this.device,
    this.os,
    this.browser,
    this.stack,
    this.requestInputJson,
  });

  /// When it happened.
  final DateTime occurredAt;

  /// The build.
  final String build;

  /// What went wrong.
  final String message;

  /// The server request.
  final String? requestId;

  /// The player.
  final String? userId;

  /// Their display name.
  final String? userName;

  /// The route, screen or job.
  final String? route;

  /// The device model.
  final String? device;

  /// The operating system.
  final String? os;

  /// The browser or HTTP client.
  final String? browser;

  /// The stack.
  final String? stack;

  /// The request's inputs, as JSON.
  final String? requestInputJson;
}

/// How often one build hit an error.
final class ErrorBuildView {
  /// Creates the view.
  const ErrorBuildView({
    required this.build,
    required this.occurrences,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  /// The build.
  final String build;

  /// Times it happened in that build.
  final int occurrences;

  /// First seen in that build.
  final DateTime firstSeenAt;

  /// Last seen in that build.
  final DateTime lastSeenAt;
}

/// An error with its samples, newest first, and its builds.
final class ErrorGroupDetail {
  /// Creates the detail.
  const ErrorGroupDetail({
    required this.group,
    required this.samples,
    required this.builds,
  });

  /// The error.
  final ErrorGroupView group;

  /// Its last occurrences, newest first.
  final List<ErrorSampleView> samples;

  /// Its builds, most recent first.
  final List<ErrorBuildView> builds;
}

/// An admin an error can be assigned to.
final class AdminRef {
  /// Creates the reference.
  const AdminRef({required this.id, required this.displayName});

  /// The account id.
  final String id;

  /// The display name.
  final String displayName;
}

/// Port over the admin side of the error log (migrations 0087, 0088).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class ErrorLogAdminRepository {
  /// Occurrences from which an open error counts as recurring.
  static const int recurringFrom = 10;

  /// How many errors each list holds.
  Future<Result<ErrorListCounts>> counts();

  /// The errors of [kind], last seen first, at most [limit]; only those
  /// from [source] and seen in [build] when given. A [problemCode] finds
  /// that code's errors in every list.
  Future<Result<List<ErrorGroupView>>> list({
    required ErrorListKind kind,
    required int limit,
    String? source,
    String? build,
    String? problemCode,
  });

  /// The error [id] with its samples and builds; null when there is none.
  Future<Result<ErrorGroupDetail?>> detail(int id);

  /// The active admins, by name.
  Future<Result<List<AdminRef>>> admins();

  /// Changes the error [id]: each argument left null keeps its value;
  /// [clearAssignee] removes the assignee; [setNotes] writes [notes] (null
  /// clears them). Returns whether the error exists.
  Future<Result<bool>> update(
    int id, {
    required DateTime at,
    String? status,
    String? severity,
    String? assigneeId,
    bool clearAssignee = false,
    bool setNotes = false,
    String? notes,
  });
}
