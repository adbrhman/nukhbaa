/// Use-case: the error log by release and by file (migration 0087).
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/platform/ports/error_release_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The errors of each recent build and the files most errors come from.
final class AdminErrorReleasesView {
  /// Creates the view.
  const AdminErrorReleasesView({required this.releases, required this.files});

  /// The recent builds, latest error first.
  final List<ErrorReleaseSummary> releases;

  /// The files with the most occurrences.
  final List<ErrorFileSummary> files;
}

/// Reads the error log by release and by file, for admins only: which build
/// brought errors in, and which files and components cause the most.
///
/// Never throws; returns a typed [Result].
final class AdminErrorReleases {
  /// Creates the use-case over its reader.
  const AdminErrorReleases({required ErrorReleaseReader reader})
    : _reader = reader;

  final ErrorReleaseReader _reader;

  /// Builds shown.
  static const int maxReleases = 15;

  /// Files shown.
  static const int maxFiles = 10;

  /// The summary, for the admin [principal].
  Future<Result<AdminErrorReleasesView>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final releases = await _reader.releases(limit: maxReleases);
    if (releases is Err<List<ErrorReleaseSummary>>) {
      return Result.err(releases.error);
    }
    final files = await _reader.files(limit: maxFiles);
    if (files is Err<List<ErrorFileSummary>>) {
      return Result.err(files.error);
    }
    return Result.ok(
      AdminErrorReleasesView(
        releases: (releases as Ok<List<ErrorReleaseSummary>>).value,
        files: (files as Ok<List<ErrorFileSummary>>).value,
      ),
    );
  }
}
