/// Quiet update check, wrapping the app's root screen.
///
/// On first frame, calls `GET /app/latest-build` (via [AppApi], never HTTP
/// directly — ADR-002 §2.8). Nothing pops up on its own: players found a
/// dialog on every release intrusive.
///
/// * Android: a newer release is recorded in [pendingUpdateProvider] and the
///   account tab shows an "update available" row. The player starts the
///   install from there ([installUpdate]) whenever they like.
/// * Web: a page running an older build than the newest release reloads by
///   itself, at launch or when the player comes back to it.
///
/// Releases are published by hand (Build Verification run from the Actions
/// tab), not on every push, so a player sees a new build at most as often as
/// the owner publishes one.
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

import '../../core/design/app_typography.dart';
import '../../core/design/app_tokens.dart';
import '../../core/platform/browser_url.dart';
import '../../core/providers.dart';
import 'in_app_updater.dart';

/// The storage key under which the last-seen release timestamp is persisted.
@visibleForTesting
const String updateLastSeenKey = 'nukhba.update_last_seen_published_at';

/// Riverpod-overridable factory for the native updater (fake in tests).
final Provider<InAppUpdater> inAppUpdaterProvider = Provider<InAppUpdater>(
  (ref) => OtaInAppUpdater(),
);

/// Reloads the web page (a no-op off the web); overridden in tests.
final Provider<void Function()> pageReloaderProvider =
    Provider<void Function()>((ref) => reloadPage);

/// Where the web build remembers the release it last offered, and when:
/// `<published_at>@<offered_at>`.
@visibleForTesting
const String updateWebOfferedKey = 'nukhba.update_web_offered';

/// The web build's memory of the release it last offered. Kept behind an
/// interface so a test can hold it in memory: platform storage has no
/// implementation under `flutter test` and never answers there.
abstract interface class UpdateOfferMemory {
  /// The stored `<published_at>@<offered_at>`, or null.
  Future<String?> read();

  /// Stores [value].
  Future<void> write(String value);
}

final class _SecureUpdateOfferMemory implements UpdateOfferMemory {
  const _SecureUpdateOfferMemory();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: updateWebOfferedKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: updateWebOfferedKey, value: value);
}

/// The web build's offer memory; overridden in tests.
final Provider<UpdateOfferMemory> updateOfferMemoryProvider =
    Provider<UpdateOfferMemory>((ref) => const _SecureUpdateOfferMemory());

/// The newer Android build the launch check found, or null when this build
/// is the newest (or the check could not tell). Hand-written like
/// `feed_refresh_signal.dart`: no build_runner output is needed for it.
class PendingUpdate extends Notifier<LatestBuildDto?> {
  @override
  LatestBuildDto? build() => null;

  /// Records [build] as available to install.
  void offer(LatestBuildDto build) => state = build;
}

/// The account tab watches this to show its "update available" row.
final pendingUpdateProvider = NotifierProvider<PendingUpdate, LatestBuildDto?>(
  PendingUpdate.new,
);

/// Wraps [child], performing one silent update check after the first frame.
class UpdateGate extends ConsumerStatefulWidget {
  /// Creates the gate around [child].
  const UpdateGate({
    required this.child,
    this.isWeb = kIsWeb,
    this.buildSha = const String.fromEnvironment('NUKHBA_BUILD_SHA'),
    super.key,
  });

  /// The app's root screen, rendered unconditionally.
  final Widget child;

  /// Whether this is the web build. A parameter only so a test can take the
  /// web path; the app always leaves the default.
  final bool isWeb;

  /// The short commit of this build, injected by CI (`--dart-define`);
  /// empty on a local run.
  final String buildSha;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  bool _checked = false;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// When the web build last asked. A page left open is asked again when
  /// the player comes back to it, at most once every [_webRecheck].
  DateTime? _lastWebCheck;
  bool _webChecking = false;
  static const Duration _webRecheck = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    if (widget.isWeb) WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only a return after the first check: the binding also reports
    // `resumed` as the app starts, which used to run a second check
    // alongside the first.
    if (state != AppLifecycleState.resumed || !widget.isWeb || !_checked) {
      return;
    }
    final DateTime? last = _lastWebCheck;
    if (last != null && DateTime.now().difference(last) < _webRecheck) return;
    unawaited(_checkWeb());
  }

  Future<void> _checkForUpdate() async {
    if (_checked) return;
    _checked = true;
    // The web build has no installer: a newer build is one reload away. It
    // used to return here, so a page left open, or one added to the home
    // screen, kept the old build and nothing told the player.
    if (widget.isWeb) {
      await _checkWeb();
      return;
    }

    final AppApi api = ref.read(appApiProvider);
    final Result<LatestBuildDto> result = await api.latestBuild();
    if (!mounted) return;
    if (result is! Ok<LatestBuildDto>) return; // offline/transient — silent

    final LatestBuildDto dto = result.value;
    final DateTime? publishedAt = DateTime.tryParse(dto.publishedAt);
    if (publishedAt == null) return; // malformed server payload — silent

    // The short commit sha of THIS build, injected by CI at
    // `flutter build apk` time. The published release lives under the tag
    // `build-<sha>`, so its download URL contains the sha of the build it
    // ships -- if that is not us, an update exists. A local `flutter run`
    // carries no sha and falls back to the timestamp this device stored.
    final String buildSha = widget.buildSha;
    if (buildSha.isNotEmpty) {
      if (dto.apkUrl.contains('/build-$buildSha/')) return; // newest already
    } else {
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
        await _remember(dto.publishedAt);
        return;
      }
      if (!publishedAt.isAfter(lastSeen)) return;
    }
    if (!mounted) return;

    // No dialog: the account tab shows a quiet row until the player updates.
    ref.read(pendingUpdateProvider.notifier).offer(dto);
  }

  /// The web build's check. The newest release and the web build come from
  /// the same commit, so a release under another commit means this page
  /// runs an older build, and it reloads by itself -- at launch, or when the
  /// player comes back after [_webRecheck]. Each release is reloaded for at
  /// most once per [_webRecheck]: the release goes up a few minutes before
  /// the web build does, and a reload in that window still gets the old one.
  Future<void> _checkWeb() async {
    final String sha = widget.buildSha;
    // A local run carries no build id: nothing to compare against.
    if (sha.isEmpty || _webChecking) return;
    _webChecking = true;
    _lastWebCheck = DateTime.now();
    try {
      await _checkWebAgainst(sha);
    } finally {
      _webChecking = false;
    }
  }

  Future<void> _checkWebAgainst(String sha) async {
    final Result<LatestBuildDto> result = await ref
        .read(appApiProvider)
        .latestBuild();
    if (!mounted || result is! Ok<LatestBuildDto>) return;
    final LatestBuildDto dto = result.value;
    if (dto.apkUrl.contains('/build-$sha/')) return;

    final UpdateOfferMemory memory = ref.read(updateOfferMemoryProvider);
    String? offered;
    try {
      offered = await memory.read();
    } on Object {
      offered = null;
    }
    if (offered != null) {
      final int at = offered.lastIndexOf('@');
      final DateTime? when = at < 0
          ? null
          : DateTime.tryParse(offered.substring(at + 1));
      if (at > 0 &&
          offered.substring(0, at) == dto.publishedAt &&
          when != null &&
          DateTime.now().difference(when) < _webRecheck) {
        return;
      }
    }
    try {
      await memory.write(
        '${dto.publishedAt}@${DateTime.now().toUtc().toIso8601String()}',
      );
    } on Object {
      // best-effort
    }
    if (!mounted) return;
    // No dialog: the new build simply loads.
    ref.read(pageReloaderProvider)();
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

/// Downloads and installs [dto] in-app ([InAppUpdater]): download progress,
/// SHA-256 integrity check and the platform installer, with a browser
/// fallback when the native path fails. Started only by the player, from the
/// account tab's "update available" row.
Future<void> installUpdate(
  BuildContext context,
  WidgetRef ref,
  LatestBuildDto dto,
) async {
  final InAppUpdater updater = ref.read(inAppUpdaterProvider);
  final Stream<UpdateProgress>? stream = updater.start(dto);
  if (stream == null) {
    if (context.mounted) await _offerBrowserFallback(context, dto);
    return;
  }
  if (!context.mounted) return;

  // The dialog returns the TERMINAL phase (no shared mutable state).
  final UpdatePhase? terminal = await showDialog<UpdatePhase>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _UpdateProgressDialog(stream: stream, onCancel: updater.cancel),
  );

  if (!context.mounted) return;
  final bool isFailure =
      terminal == UpdatePhase.downloadFailed ||
      terminal == UpdatePhase.checksumFailed ||
      terminal == UpdatePhase.installFailed ||
      terminal == UpdatePhase.failed;
  if (isFailure) {
    await _offerBrowserFallback(context, dto);
  }
}

Future<void> _offerBrowserFallback(
  BuildContext context,
  LatestBuildDto dto,
) async {
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
  // event, the user's Cancel tap, the stream closing and the watchdog can
  // otherwise all fire.
  bool _settled = false;

  /// Bounds the whole dialog. `ota_update` can close its stream without ever
  /// emitting a terminal event -- the usual shape once the platform installer
  /// takes over at `installing` -- and it can also simply go quiet mid
  /// download. This dialog is `barrierDismissible: false` and offers a
  /// control only while downloading, so before this bound existed there was
  /// no way out of it at all: the app had to be killed.
  static const Duration _silenceTimeout = Duration(seconds: 90);
  Timer? _watchdog;

  UpdateProgress _current = const UpdateProgress(
    UpdatePhase.downloading,
    percent: 0,
  );

  @override
  void initState() {
    super.initState();
    _armWatchdog();
    _sub = widget.stream.listen(
      (p) {
        if (!mounted || _settled) return;
        setState(() => _current = p);
        if (p.isTerminal) {
          final delay = p.phase == UpdatePhase.completed
              ? const Duration(milliseconds: 600)
              : Duration.zero;
          Future<void>.delayed(delay, () => _settle(p.phase));
        } else {
          _armWatchdog();
        }
      },
      // An error on the plugin's stream used to reach nobody: the dialog kept
      // spinning and the zone reported an unhandled error.
      onError: (Object error) => _settle(UpdatePhase.failed),
      onDone: () {
        if (_settled || _current.isTerminal) return;
        // Closed with no terminal event. `installing` means the platform
        // installer is already up (the parent treats it as a non-failure);
        // anything else is a failure worth the browser fallback.
        _settle(
          _current.phase == UpdatePhase.installing
              ? UpdatePhase.installing
              : UpdatePhase.failed,
        );
      },
    );
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_silenceTimeout, () => _settle(UpdatePhase.failed));
  }

  /// Closes the dialog exactly once, handing [phase] back to the parent.
  void _settle(UpdatePhase phase) {
    if (_settled || !mounted) return;
    _settled = true;
    _watchdog?.cancel();
    Navigator.of(context).pop(phase);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
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
              style: TextStyle(
                fontSize: AppFontSize.s12,
                color: context.tokens.error,
              ),
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
              _settle(UpdatePhase.cancelled);
            },
            child: const Text('إلغاء'),
          )
        else
          // Verifying/installing offered no control at all, so a plugin that
          // went quiet left a dialog the user could not dismiss.
          TextButton(
            key: const Key('update.progress.close'),
            onPressed: () => _settle(_current.phase),
            child: const Text('إغلاق'),
          ),
      ],
    );
  }
}
