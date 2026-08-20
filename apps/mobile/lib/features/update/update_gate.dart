/// Best-effort in-app update nudge, wrapping the app's root screen.
///
/// On first frame, calls `GET /app/latest-build` (via [AppApi], never HTTP
/// directly — ADR-002 §2.8). The server's release workflow publishes to a
/// single rolling `latest` tag with no usable semver, so there is no
/// "current app version" to compare against — instead this compares the
/// release's `published_at` against the last one this device already saw
/// (persisted in `flutter_secure_storage`, the same mechanism already used
/// by [SecureTokenStore] — no new dependency). A strictly newer publish
/// triggers a dismissible dialog offering to open the `.apk` download in the
/// system browser via `url_launcher`.
///
/// Silent on any failure (offline, transient server error, malformed
/// response, storage read failure): this is a nudge, never a gate on app
/// usage — [child] always renders immediately.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';

/// The storage key under which the last-seen release timestamp is
/// persisted (ISO-8601 string).
@visibleForTesting
const String updateLastSeenKey = 'nukhba.update_last_seen_published_at';

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
      lastSeenRaw = null; // treat a storage read failure as "never seen"
    }
    final DateTime? lastSeen = lastSeenRaw == null
        ? null
        : DateTime.tryParse(lastSeenRaw);

    // First-ever check on this device: establish the baseline silently
    // (a fresh install is already running roughly this release) instead of
    // nagging immediately after first launch.
    if (lastSeen == null) {
      await _remember(dto.publishedAt);
      return;
    }

    if (!publishedAt.isAfter(lastSeen)) return;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('يتوفر تحديث جديد'),
        content: const Text('يتوفر إصدار أحدث من التطبيق. يُنصح بالتحديث.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await launchUrl(
                Uri.parse(dto.apkUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('تنزيل'),
          ),
        ],
      ),
    );

    // Remember this release regardless of the user's choice, so the same
    // release does not re-prompt on every subsequent launch.
    await _remember(dto.publishedAt);
  }

  Future<void> _remember(String publishedAt) async {
    try {
      await _storage.write(key: updateLastSeenKey, value: publishedAt);
    } on Object {
      // Best-effort only — a failed write just means this release may
      // prompt again next launch, which is safe.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
