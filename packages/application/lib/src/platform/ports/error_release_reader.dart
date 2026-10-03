import 'package:shared/shared.dart';

/// The errors one build hit (migration 0087).
final class ErrorReleaseSummary {
  /// Creates the summary.
  const ErrorReleaseSummary({
    required this.build,
    required this.errors,
    required this.critical,
    required this.occurrences,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  /// The build.
  final String build;

  /// Distinct errors it hit.
  final int errors;

  /// Of which marked critical.
  final int critical;

  /// Occurrences in it.
  final int occurrences;

  /// Its first error.
  final DateTime firstSeenAt;

  /// Its latest error.
  final DateTime lastSeenAt;
}

/// The errors one file is the location of.
final class ErrorFileSummary {
  /// Creates the summary.
  const ErrorFileSummary({
    required this.file,
    required this.errors,
    required this.occurrences,
  });

  /// The file (`package:mobile/...`, `routes/...`).
  final String file;

  /// Distinct errors located there.
  final int errors;

  /// Their occurrences.
  final int occurrences;
}

/// Port over the per-build and per-file summaries of the error log.
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class ErrorReleaseReader {
  /// The [limit] most recent builds, latest error first.
  Future<Result<List<ErrorReleaseSummary>>> releases({required int limit});

  /// The [limit] files with the most occurrences.
  Future<Result<List<ErrorFileSummary>>> files({required int limit});
}
