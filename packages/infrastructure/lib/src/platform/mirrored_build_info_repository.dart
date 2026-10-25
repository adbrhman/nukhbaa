import 'dart:async';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// The newest build with each APK's address moved to the web mirror
/// (`https://nukhbaa.app/apk/`) once the mirror serves that very file
/// (script 144).
///
/// GitHub's download host is very slow in Yemen without a VPN, while
/// nukhbaa.app (the Northflank web mirror) is not. The Deploy Web workflow
/// copies each release's APKs to the mirror under their release names
/// (`nukhbaa-<abi>-<sha>.apk`), a few minutes after the release itself, so
/// an address is moved only after a `HEAD` on the mirror answers `200` with
/// the APK type; until then the GitHub address stays. Every build reads the
/// address from the server (`GET /app/latest-build`), so the old ones
/// download from the mirror too. The SHA-256 stays the release's: the
/// in-app updater checks the file against it whatever the host.
///
/// Only names that carry the commit are moved: such a file never changes,
/// so a mirror that answered once is not asked again. A miss is asked
/// again after [recheck]. Everything else of the build passes through.
///
/// [LatestBuild.apkUrl] keeps GitHub's address (script 145): every build
/// decides it is the newest when that address holds `/build-<its sha>/`
/// (`UpdateGate`, on Android and on the web), so a mirrored address there
/// offered the update forever, even right after it was installed. The
/// in-app updater downloads from [LatestBuild.assets], the file for the
/// phone's processor, so the download still comes from the mirror.
final class MirroredBuildInfoRepository implements BuildInfoRepository {
  /// Wraps [inner]; [base] is the mirror's folder (ending in `/`), or
  /// `null` to leave every address as [inner] gives it.
  MirroredBuildInfoRepository(
    this._inner,
    this._httpClient, {
    required Uri? base,
    this.recheck = const Duration(minutes: 2),
    this.timeout = const Duration(seconds: 5),
    DateTime Function() now = DateTime.now,
  }) : _base = base,
       _now = now;

  /// The mirror folder from `NUKHBA_APK_MIRROR` in [environment]:
  /// `https://nukhbaa.app/apk/` when absent or empty, `null` for `off`.
  static Uri? baseFrom(Map<String, String> environment) {
    final String raw = environment['NUKHBA_APK_MIRROR']?.trim() ?? '';
    if (raw.toLowerCase() == 'off') {
      return null;
    }
    final String value = raw.isEmpty ? 'https://nukhbaa.app/apk/' : raw;
    final Uri? uri = Uri.tryParse(value.endsWith('/') ? value : '$value/');
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri
        : null;
  }

  final BuildInfoRepository _inner;
  final http.Client _httpClient;
  final Uri? _base;
  final DateTime Function() _now;

  /// How long a file the mirror did not serve waits before it is asked
  /// again.
  final Duration recheck;

  /// The longest a `HEAD` on the mirror may take.
  final Duration timeout;

  /// The release names the mirror serves (never asked again).
  final Set<String> _served = <String>{};

  /// When each name the mirror did not serve was last asked.
  final Map<String, DateTime> _missedAt = <String, DateTime>{};

  /// The `HEAD`s in flight, one per name.
  final Map<String, Future<bool>> _asking = <String, Future<bool>>{};

  /// A release APK name: the ABI and the commit, so the file never changes.
  static final RegExp _releaseName = RegExp(
    r'^nukhbaa-(arm64-v8a|armeabi-v7a|x86_64|x86)-[0-9a-f]{7}\.apk$',
  );

  @override
  Future<Result<LatestBuild>> fetchLatest() async {
    final Result<LatestBuild> latest = await _inner.fetchLatest();
    final Uri? base = _base;
    if (base == null || latest is! Ok<LatestBuild>) {
      return latest;
    }
    final LatestBuild build = latest.value;
    final List<BuildAsset> assets = <BuildAsset>[
      for (final BuildAsset asset in build.assets)
        BuildAsset(
          abi: asset.abi,
          url: await _addressOf(asset.url, base),
          sha256: asset.sha256,
        ),
    ];
    return Result.ok(
      LatestBuild(
        publishedAt: build.publishedAt,
        // GitHub's, always: the apps compare it with their own sha.
        apkUrl: build.apkUrl,
        sha256: build.sha256,
        assets: assets,
        buildNumber: build.buildNumber,
        minSupportedBuild: build.minSupportedBuild,
      ),
    );
  }

  /// The mirror's address for [url] when the mirror serves that file,
  /// else [url].
  Future<String> _addressOf(String url, Uri base) async {
    final Uri? source = Uri.tryParse(url);
    final String name = source == null || source.pathSegments.isEmpty
        ? ''
        : source.pathSegments.last;
    if (!_releaseName.hasMatch(name)) {
      return url;
    }
    final Uri mirrored = base.resolve(name);
    return await _serves(name, mirrored) ? mirrored.toString() : url;
  }

  Future<bool> _serves(String name, Uri mirrored) {
    if (_served.contains(name)) {
      return Future<bool>.value(true);
    }
    final DateTime? missed = _missedAt[name];
    if (missed != null && _now().difference(missed) < recheck) {
      return Future<bool>.value(false);
    }
    return _asking[name] ??= _ask(mirrored).then((bool served) {
      // Dropped here, not in a whenComplete returning the removed future:
      // that would wait on itself.
      _asking.remove(name);
      if (served) {
        _served.add(name);
        _missedAt.remove(name);
      } else {
        _missedAt[name] = _now();
      }
      return served;
    });
  }

  Future<bool> _ask(Uri mirrored) async {
    try {
      final http.Response response = await _httpClient
          .head(mirrored)
          .timeout(timeout);
      final String type = response.headers['content-type'] ?? '';
      return response.statusCode == 200 &&
          type.contains('application/vnd.android.package-archive');
    } on Object {
      return false;
    }
  }
}
