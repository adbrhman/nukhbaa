import 'package:shared/shared.dart';

/// How bad an error is, most severe first (migration 0087).
enum ErrorSeverity {
  /// Points, money or the whole service at stake.
  critical,

  /// A feature is broken for whoever hits it.
  high,

  /// A failure the player can retry past.
  medium,

  /// Noise worth keeping an eye on.
  low,
}

/// One occurrence of an error, already redacted and fingerprinted, as
/// `ops.record_error()` takes it (migration 0087).
final class ErrorOccurrence {
  /// Creates an occurrence.
  const ErrorOccurrence({
    required this.fingerprint,
    required this.problemCode,
    required this.source,
    required this.errorType,
    required this.message,
    required this.severity,
    required this.build,
    required this.occurredAt,
    this.errorCode,
    this.locationFile,
    this.locationLine,
    this.locationSymbol,
    this.userId,
    this.requestId,
    this.route,
    this.device,
    this.os,
    this.browser,
    this.stack,
    this.requestInputJson,
  });

  /// 16 hex digits identifying the error.
  final String fingerprint;

  /// The 4 characters a player reads out.
  final String problemCode;

  /// `server`, `android`, `ios` or `web`.
  final String source;

  /// The error's runtime type (`StateError`, `AppError`).
  final String errorType;

  /// The stable `AppError` code, when there is one.
  final String? errorCode;

  /// What went wrong, redacted.
  final String message;

  /// Where: the first frame of the stack that identifies the error.
  final String? locationFile;

  /// The line of [locationFile], for display.
  final int? locationLine;

  /// The member running at [locationFile].
  final String? locationSymbol;

  /// How bad it is.
  final ErrorSeverity severity;

  /// The build that hit it (short commit sha).
  final String build;

  /// When the server received it.
  final DateTime occurredAt;

  /// The signed-in player, when there was one.
  final String? userId;

  /// The server request it happened in (`X-Request-Id`).
  final String? requestId;

  /// `GET /seasons/:id`, a screen, or `job rescore`.
  final String? route;

  /// The device model.
  final String? device;

  /// The operating system and version.
  final String? os;

  /// The browser (web) or the HTTP client (server).
  final String? browser;

  /// The whole stack, redacted.
  final String? stack;

  /// The request's inputs as a JSON object, redacted.
  final String? requestInputJson;
}

/// The error as it stands after one occurrence was kept.
final class RecordedError {
  /// Creates the outcome.
  const RecordedError({
    required this.groupId,
    required this.occurrences,
    required this.status,
    required this.severity,
    required this.usersAffected,
    required this.isNew,
    required this.reopened,
  });

  /// The error's row in `ops.error_groups`.
  final int groupId;

  /// Occurrences so far, this one included.
  final int occurrences;

  /// `new`, `in_progress`, `fixed`, `verified` or `ignored`.
  final String status;

  /// The error's severity as stored.
  final String severity;

  /// Distinct signed-in players hit so far.
  final int usersAffected;

  /// Whether this was the first occurrence ever.
  final bool isNew;

  /// Whether a fixed error just came back in a build that never had it.
  final bool reopened;
}

/// Port over `ops.record_error()` (migration 0087).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class ErrorLogRepository {
  /// Keeps one [occurrence].
  Future<Result<RecordedError>> record(ErrorOccurrence occurrence);
}
