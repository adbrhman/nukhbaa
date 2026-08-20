import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the platform "App" surface of `apps/server`.
///
/// Wraps the one ratified route:
///   * `GET /app/latest-build` -> [LatestBuildDto] (newest published Android
///     build, sourced from GitHub Releases server-side —
///     `routes/app/latest-build/index.dart`).
///
/// Deliberately unauthenticated: the app calls this on launch, possibly
/// before sign-in, to decide whether to prompt an in-app update. A pure
/// read, no side effect; returns a typed [Result] and never throws.
final class AppApi {
  /// Creates the App client over the shared [ApiTransport].
  const AppApi(this._transport);

  final ApiTransport _transport;

  /// `GET /app/latest-build` — the newest published Android build.
  Future<Result<LatestBuildDto>> latestBuild() {
    return _transport.getObject<LatestBuildDto>(
      '/app/latest-build',
      parse: LatestBuildDto.fromJson,
    );
  }
}
