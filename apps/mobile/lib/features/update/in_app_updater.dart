/// In-app OTA updater — the PRIMARY update path (ADR-002 §2.8 exception).
///
/// Downloads the ABI-matched release APK via NATIVE Android (`ota_update`, no
/// Dart HTTP), verifies its SHA-256, then triggers the platform installer. The
/// update METADATA (per-ABI URL + checksum) comes only from the server through
/// `api_client`/`contracts`; this class never talks to the network in Dart.
///
/// The plugin is wrapped behind [InAppUpdater] so [UpdateGate] depends on a
/// testable seam, never on native calls directly.
///
/// GOOGLE PLAY NOTE: this path is for EXTERNAL (GitHub/APK) distribution only —
/// it uses REQUEST_INSTALL_PACKAGES + the native package installer. If the app
/// is ever shipped through Google Play, this path MUST be replaced by the Play
/// In-App Updates API; sideloading an APK violates Play policy. See ADR note in
/// docs and `update_gate.dart`.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ota_update/ota_update.dart';

/// A single UI-facing phase of the update.
enum UpdatePhase {
  /// Bytes are being downloaded (see [UpdateProgress.percent]).
  downloading,

  /// Checksum verified; installation intent has been triggered. For a normal
  /// (non-system) sideloaded app this is effectively terminal-success: the OS
  /// shows its own install UI and does not report completion back to us.
  installing,

  /// Installation reported complete (PackageInstaller path only).
  completed,

  /// The user cancelled the download.
  cancelled,

  /// Download failed (network/native).
  downloadFailed,

  /// SHA-256 mismatch — the file was corrupted or tampered with in transit.
  /// NOTE: this proves INTEGRITY against the published checksum, NOT publisher
  /// AUTHENTICITY. Authenticity is enforced by the Android APK signing key: the
  /// OS refuses to install an update signed by a different key.
  checksumFailed,

  /// Installation failed or install permission was refused.
  installFailed,

  /// Any other native/plugin error, or no installable asset for this device.
  failed,
}

/// A progress snapshot emitted by [InAppUpdater.start].
class UpdateProgress {
  /// Creates a progress snapshot.
  const UpdateProgress(this.phase, {this.percent, this.message});

  /// The current phase.
  final UpdatePhase phase;

  /// Download percentage 0–100 while [phase] is [UpdatePhase.downloading].
  final int? percent;

  /// Optional diagnostic detail (never contains secrets/tokens).
  final String? message;

  /// True once the flow reached a phase the UI should not advance past.
  bool get isTerminal =>
      phase == UpdatePhase.completed ||
      phase == UpdatePhase.cancelled ||
      phase == UpdatePhase.downloadFailed ||
      phase == UpdatePhase.checksumFailed ||
      phase == UpdatePhase.installFailed ||
      phase == UpdatePhase.failed;

  /// True on any non-cancel failure — the caller should offer the fallback.
  bool get isFailure =>
      phase == UpdatePhase.downloadFailed ||
      phase == UpdatePhase.checksumFailed ||
      phase == UpdatePhase.installFailed ||
      phase == UpdatePhase.failed;
}

/// The seam [UpdateGate] depends on. The production impl wraps `ota_update`;
/// tests supply a fake that emits a scripted [UpdateProgress] stream.
abstract interface class InAppUpdater {
  /// Selects the asset matching the device ABI, downloads + verifies + installs
  /// it, and reports progress. Never throws; failures arrive as terminal
  /// [UpdateProgress] events. Returns `null` when no installable/verifiable
  /// asset exists for this device (caller must use the browser fallback).
  Stream<UpdateProgress>? start(LatestBuildDto build);

  /// Cancels an in-flight download. Best-effort.
  Future<void> cancel();
}

/// Production [InAppUpdater] over the `ota_update` plugin.
class OtaInAppUpdater implements InAppUpdater {
  /// Creates the updater, optionally injecting seams for tests.
  OtaInAppUpdater({OtaUpdate? ota, DeviceInfoPlugin? deviceInfo})
    : _ota = ota ?? OtaUpdate(),
      _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final OtaUpdate _ota;
  final DeviceInfoPlugin _deviceInfo;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    final controller = StreamController<UpdateProgress>();
    unawaited(_run(build, controller));
    return controller.stream;
  }

  Future<void> _run(
    LatestBuildDto build,
    StreamController<UpdateProgress> out,
  ) async {
    try {
      final selected = await _selectAsset(build);
      if (selected == null) {
        out.add(
          const UpdateProgress(
            UpdatePhase.failed,
            message: 'no_matching_verifiable_asset',
          ),
        );
        await out.close();
        return;
      }

      // HTTPS-only: never hand a cleartext URL to the native downloader.
      final uri = Uri.tryParse(selected.url);
      if (uri == null || uri.scheme.toLowerCase() != 'https') {
        out.add(
          const UpdateProgress(
            UpdatePhase.failed,
            message: 'insecure_or_invalid_url',
          ),
        );
        await out.close();
        return;
      }

      // Checksum must be a well-formed lowercase hex SHA-256.
      if (!_hex64.hasMatch(selected.sha256.toLowerCase())) {
        out.add(
          const UpdateProgress(
            UpdatePhase.failed,
            message: 'invalid_checksum_format',
          ),
        );
        await out.close();
        return;
      }

      _ota
          .execute(
            selected.url,
            destinationFilename: 'nukhbaa-update.apk',
            sha256checksum: selected.sha256.toLowerCase(),
          )
          .listen(
            (event) => out.add(_map(event)),
            onError: (Object e) {
              out.add(UpdateProgress(UpdatePhase.failed, message: '$e'));
              unawaited(out.close());
            },
            onDone: () => unawaited(out.close()),
          );
    } catch (e) {
      out.add(UpdateProgress(UpdatePhase.failed, message: '$e'));
      await out.close();
    }
  }

  /// Picks the asset whose ABI matches the device. Preference order:
  ///   1) ota_update's own getAbi() (guarded — API may vary by version);
  ///   2) device supportedAbis (most-preferred first);
  ///   3) the DTO's primary apkUrl+sha256 as a universal fallback (only if a
  ///      checksum was published for it).
  Future<_AbiAsset?> _selectAsset(LatestBuildDto build) async {
    final assets = build.assets;
    if (assets.isNotEmpty) {
      final candidates = <String>[];
      final pref = await _preferredAbi();
      if (pref != null && pref.isNotEmpty) candidates.add(pref);
      candidates.addAll(await _deviceAbis());
      for (final abi in candidates) {
        for (final a in assets) {
          if (a.abi == abi) return _AbiAsset(a.url, a.sha256);
        }
      }
    }
    final primarySha = build.sha256;
    if (primarySha != null && primarySha.isNotEmpty) {
      return _AbiAsset(build.apkUrl, primarySha);
    }
    return null;
  }

  /// ota_update exposes an experimental ABI getter for split-apk selection.
  /// The exact method name/signature is not stable across versions, so this is
  /// fully guarded: any failure just falls through to [_deviceAbis].
  Future<String?> _preferredAbi() async {
    try {
      // ignore: avoid_dynamic_calls
      final dynamic result = await (_ota as dynamic).getAbi();
      if (result is String) return result;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _deviceAbis() async {
    try {
      final info = await _deviceInfo.androidInfo;
      return info.supportedAbis;
    } catch (_) {
      return const <String>[];
    }
  }

  UpdateProgress _map(OtaEvent e) {
    switch (e.status) {
      case OtaStatus.DOWNLOADING:
        return UpdateProgress(
          UpdatePhase.downloading,
          percent: int.tryParse(e.value ?? ''),
        );
      case OtaStatus.INSTALLING:
        return const UpdateProgress(UpdatePhase.installing);
      case OtaStatus.INSTALLATION_DONE:
        return const UpdateProgress(UpdatePhase.completed);
      case OtaStatus.CANCELED:
        return const UpdateProgress(UpdatePhase.cancelled);
      case OtaStatus.DOWNLOAD_ERROR:
      case OtaStatus.ALREADY_RUNNING_ERROR:
        return UpdateProgress(UpdatePhase.downloadFailed, message: e.value);
      case OtaStatus.CHECKSUM_ERROR:
        return UpdateProgress(UpdatePhase.checksumFailed, message: e.value);
      case OtaStatus.INSTALLATION_ERROR:
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        return UpdateProgress(UpdatePhase.installFailed, message: e.value);
      case OtaStatus.INTERNAL_ERROR:
        return UpdateProgress(UpdatePhase.failed, message: e.value);
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _ota.cancel();
    } catch (_) {
      // best-effort
    }
  }
}

class _AbiAsset {
  const _AbiAsset(this.url, this.sha256);
  final String url;
  final String sha256;
}
