import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for discovering the newest published Android build (Repository
/// pattern — Application ADR, Section 9). Implemented in Infrastructure over
/// GitHub Releases; the application depends on this interface, never on a
/// concrete HTTP client.
abstract interface class BuildInfoRepository {
  /// Returns `Ok(LatestBuild)` for the newest published release, or
  /// `Err(transient)` if the source could not be reached or carried no
  /// `.apk` asset.
  Future<Result<LatestBuild>> fetchLatest();
}
