/// Best-effort in-app update nudge, wrapping the app's root screen.
///
/// On first frame, calls `GET /app/latest-build` (via [AppApi], never HTTP
/// directly — ADR-002 §2.8). The server publishes to a rolling `latest` tag
/// with no usable semver, so this compares the release's `published_at`
/// against the last one this device already saw (persisted in
/// `flutter_secure_storage`). A strictly newer publish shows a dismissible
/// dialog.
///
/// PRIMARY download path: [InAppUpdater] (native OTA) — download progress,
/// SHA-256 INTEGRITY verification and the platform installer all happen
/// IN-APP; the release APK is NEVER handed to Chrome in the normal path. Only
/// if the native path fails (plugin/permission/native/checksum error, or no
/// installable asset) does the user get an explicit "فتح صفحة التنزيل"
/// fallback that opens the browser via `url_launcher`.
///
/// SECURITY: SHA-256 verification proves the downloaded file matches the
/// published checksum (integrity). It does NOT prove the publisher's identity;
/// that is enforced by Android refusing to install an update signed with a
/// different APK signing key. Release APKs MUST be signed with a stable key.
///
/// GOOGLE PLAY: this native-install path is for EXTERNAL (GitHub/APK)
/// distribution only. A future Play build must switch to the Play In-App
/// Updates API instead.
///
/// Silent on any check failure (offline, transient server error, malformed
/// response): [child] always renders immediately.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import 'in_app_updater.dart';

/// The storage key under which the last-seen release timestamp is persisted.
@visibleForTesting
const String updateLastSeenKey = 'nukhba.update_last_seen_published_at';

/// Riverpod-overridable factory for the native updater (fake in tests).
final Provider<InAppUpdater> inAppUpdaterProvider = Provider<InAppUpdater>(
  (ref) => OtaInAppUpdater(),
);

/// Wraps [child], performing one silent update check after the first frame.
class UpdateGate extends ConsumerStatefulWidget {
  /// Creates the gate around [child].
  const UpdateGate({required this.child, super.key});

  /// The app's root screen, rendered unconditionally.
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _checked = false;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_checked) return;
    _checked = true;
    // PWA updates via the browser/service worker on redeploy — native
    // OTA (ota_update plugin) has no web implementation and would hang.
    if (kIsWeb) return;

    final AppApi api = ref.read(appApiProvider);
    final Result<LatestBuildDto> result = await api.latestBuild();
    if (!mounted) return;
    if (result is! Ok<LatestBuildDto>) return; // offline/transient — silent

    final LatestBuildDto dto = result.value;
    final DateTime? publishedAt = DateTime.tryParse(dto.publishedAt);
    if (publishedAt == null) return; // malformed server payload — silent

    String? lastSeenRaw;
    try {
      lastSeenRaw = await _storage.read(key: updateLastSeenKey);
    } on Object {
      lastSeenRaw = null;
    }
    final DateTime? lastSeen = lastSeenRaw == null
        ? null
        : DateTime.tryParse(lastSeenRaw);

    if (lastSeen == null) {
      await _remember(dto.publishedAt); // fresh install baseline
      return;
    }
    if (!publishedAt.isAfter(lastSeen)) return;
    if (!mounted) return;

    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('يتوفر تحديث جديد'),
        content: const Text('يتوفر إصدار أحدث من التطبيق. يُنصح بالتحديث.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تنزيل'),
          ),
        ],
      ),
    );

    // Remember regardless, so the same release does not re-prompt every launch.
    await _remember(dto.publishedAt);

    if (proceed == true && mounted) {
      await _runInAppUpdate(dto);
    }
  }

  Future<void> _runInAppUpdate(LatestBuildDto dto) async {
    final InAppUpdater updater = ref.read(inAppUpdaterProvider);
    final Stream<UpdateProgress>? stream = updater.start(dto);
    if (stream == null) {
      if (mounted) await _offerBrowserFallback(dto);
      return;
    }
    if (!mounted) return;

    // The dialog returns the TERMINAL phase (no shared mutable state).
    final UpdatePhase? terminal = await showDialog<UpdatePhase>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _UpdateProgressDialog(stream: stream, onCancel: updater.cancel),
    );

    if (!mounted) return;
    final bool isFailure =
        terminal == UpdatePhase.downloadFailed ||
        terminal == UpdatePhase.checksumFailed ||
        terminal == UpdatePhase.installFailed ||
        terminal == UpdatePhase.failed;
    if (isFailure) {
      await _offerBrowserFallback(dto);
    }
  }

  Future<void> _offerBrowserFallback(LatestBuildDto dto) async {
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعذّر التحديث داخل التطبيق'),
        content: const Text(
          'حدثت مشكلة أثناء التحديث التلقائي. يمكنك فتح صفحة التنزيل '
          'لإكمال التحديث يدويًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('فتح صفحة التنزيل'),
          ),
        ],
      ),
    );
    if (open == true) {
      final Uri uri = Uri.parse(dto.apkUrl);
      if (uri.scheme.toLowerCase() == 'https') {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _remember(String publishedAt) async {
    try {
      await _storage.write(key: updateLastSeenKey, value: publishedAt);
    } on Object {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// In-app progress dialog: RTL Arabic, non-dismissible. Pops with the terminal
/// [UpdatePhase] so the parent can decide (fallback or not) without any shared
/// mutable state.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({required this.stream, required this.onCancel});

  final Stream<UpdateProgress> stream;
  final Future<void> Function() onCancel;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  StreamSubscription<UpdateProgress>? _sub;
  // Guards against a double Navigator.pop: the plugin's terminal stream
  // event and the user's Cancel tap can otherwise both fire.
  bool _settled = false;
  UpdateProgress _current = const UpdateProgress(
    UpdatePhase.downloading,
    percent: 0,
  );

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen((p) {
      if (!mounted || _settled) return;
      setState(() => _current = p);
      if (p.isTerminal) {
        final delay = p.phase == UpdatePhase.completed
            ? const Duration(milliseconds: 600)
            : Duration.zero;
        Future<void>.delayed(delay, () {
          if (mounted && !_settled) {
            _settled = true;
            Navigator.of(context).pop(p.phase);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String get _title => switch (_current.phase) {
    UpdatePhase.downloading => 'جارٍ التنزيل',
    UpdatePhase.installing => 'جارٍ التحقق والتثبيت',
    UpdatePhase.completed => 'اكتمل التحديث',
    UpdatePhase.cancelled => 'تم الإلغاء',
    UpdatePhase.downloadFailed => 'فشل التنزيل',
    UpdatePhase.checksumFailed => 'فشل التحقق من سلامة الملف',
    UpdatePhase.installFailed => 'فشل التثبيت',
    UpdatePhase.failed => 'تعذّر التحديث',
  };

  @override
  Widget build(BuildContext context) {
    final int pct = _current.percent ?? 0;
    final bool showBar = _current.phase == UpdatePhase.downloading;
    return AlertDialog(
      title: Text(_title, textAlign: TextAlign.right),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBar) ...[
            LinearProgressIndicator(value: pct / 100.0),
            const SizedBox(height: 12),
            Text('$pct%', textAlign: TextAlign.center),
          ] else if (_current.phase == UpdatePhase.installing)
            const Center(child: CircularProgressIndicator()),
          // TEMP DIAGNOSTIC: surface the raw native error on-screen so it
          // can be read without adb/logcat. Remove once root-caused.
          if (_current.message != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              _current.message!,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        if (_current.phase == UpdatePhase.downloading)
          TextButton(
            onPressed: () {
              // Best-effort native cancel — never let the UI hang
              // waiting for a terminal event the plugin might not send.
              unawaited(widget.onCancel());
              if (!_settled && mounted) {
                _settled = true;
                Navigator.of(context).pop(UpdatePhase.cancelled);
              }
            },
            child: const Text('إلغاء'),
          ),
      ],
    );
  }
}
