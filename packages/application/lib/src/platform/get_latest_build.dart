import 'package:application/src/platform/ports/build_info_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: report the newest published Android build so the client can
/// prompt an in-app update (Platform update-check slice).
final class GetLatestBuild {
  /// Creates the use-case with its required [BuildInfoRepository] port.
  const GetLatestBuild(this._buildInfoRepository);

  final BuildInfoRepository _buildInfoRepository;

  /// Executes the check. Never throws; returns a typed [Result].
  Future<Result<LatestBuild>> call() => _buildInfoRepository.fetchLatest();
}
