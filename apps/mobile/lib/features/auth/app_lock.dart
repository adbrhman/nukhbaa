/// Optional fingerprint unlock: a user who switched it on opens the app with
/// a fingerprint instead of seeing their session straight away.
///
/// The session itself never changes here. It persists week after week
/// through the refresh token; this layer only decides whether a cold start
/// opens onto it directly ([AppLockState.open]) or behind the fingerprint
/// prompt ([AppLockState.locked]). A password sign-in never meets the lock:
/// any signed-out state opens it, so it only guards a restored session.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/biometric_unlock.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import 'session_controller.dart';
import 'session_state.dart';

/// Where the app stands against the fingerprint lock.
enum AppLockState {
  /// The saved choice is still being read.
  checking,

  /// Fingerprint unlock is on and this restored session is not unlocked yet.
  locked,

  /// Nothing stands between the user and the app.
  open,
}

/// The app-wide lock state; lives for the whole process, so the lock is met
/// once per cold start.
final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// What the account screen needs to draw the fingerprint switch.
typedef BiometricSetting = ({bool available, bool enabled});

/// Whether this device can use fingerprint unlock, and whether it is on.
final biometricSettingProvider = FutureProvider.autoDispose<BiometricSetting>((
  ref,
) async {
  final bool available = await ref
      .read(biometricAuthenticatorProvider)
      .isAvailable();
  if (!available) return (available: false, enabled: false);
  final bool enabled = await _readEnabled(
    ref.read(biometricPreferenceStoreProvider),
  );
  return (available: true, enabled: enabled);
});

/// The saved choice; an unreadable store reads as "off", never as a crash.
Future<bool> _readEnabled(BiometricPreferenceStore store) async {
  try {
    return await store.isEnabled();
  } on Object {
    return false;
  }
}

/// Owns [AppLockState].
class AppLockController extends Notifier<AppLockState> {
  @override
  AppLockState build() {
    // Signed out, by choice or by a refused renewal: there is no session to
    // guard, and the next sign-in is a password one that must not meet the
    // lock.
    ref.listen<AsyncValue<SessionState>>(sessionControllerProvider, (_, next) {
      final SessionState? session = next.value;
      if (session is SessionUnauthenticated ||
          (session is SessionFailed && !session.canRetryRestore)) {
        state = AppLockState.open;
      }
    });
    unawaited(_load());
    return AppLockState.checking;
  }

  Future<void> _load() async {
    final bool enabled = await _readEnabled(
      ref.read(biometricPreferenceStoreProvider),
    );
    if (state == AppLockState.checking) {
      state = enabled ? AppLockState.locked : AppLockState.open;
    }
  }

  /// Shows the fingerprint prompt; opens the app when it is passed.
  Future<bool> unlock() async {
    final bool passed = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(reason: 'ضع بصمتك للدخول إلى نُخبة');
    if (passed) state = AppLockState.open;
    return passed;
  }

  /// Switches fingerprint unlock on, after the user proves the fingerprint
  /// works. False when the device cannot, or the prompt was not passed.
  Future<bool> enable() async {
    final BiometricAuthenticator authenticator = ref.read(
      biometricAuthenticatorProvider,
    );
    if (!await authenticator.isAvailable()) return false;
    final bool passed = await authenticator.authenticate(
      reason: 'ضع بصمتك لتفعيل الدخول بالبصمة',
    );
    if (!passed) return false;
    final BiometricPreferenceStore store = ref.read(
      biometricPreferenceStoreProvider,
    );
    await store.setEnabled(enabled: true);
    await store.markOffered();
    state = AppLockState.open;
    return true;
  }

  /// Switches fingerprint unlock off.
  Future<void> disable() async {
    await ref.read(biometricPreferenceStoreProvider).setEnabled(enabled: false);
    state = AppLockState.open;
  }
}

/// Offers fingerprint unlock once, right after a sign-in, when the device
/// has a fingerprint enrolled. Declining is final: the switch in the account
/// screen stays available.
Future<void> offerBiometricUnlock(BuildContext context, WidgetRef ref) async {
  final BiometricPreferenceStore store = ref.read(
    biometricPreferenceStoreProvider,
  );
  try {
    if (await store.wasOffered() || await store.isEnabled()) return;
    if (!await ref.read(biometricAuthenticatorProvider).isAvailable()) return;
    await store.markOffered();
  } on Object {
    return;
  }
  if (!context.mounted) return;
  final bool? accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('appLock.offer'),
      icon: const Icon(Icons.fingerprint_rounded, size: 40),
      title: const Text('الدخول بالبصمة'),
      content: const Text(
        'افتح نُخبة ببصمتك فقط، بدون كلمة مرور. '
        'يمكنك إيقافها في أي وقت من صفحة الحساب.',
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('appLock.offer.later'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('ليس الآن'),
        ),
        FilledButton(
          key: const Key('appLock.offer.enable'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('تفعيل'),
        ),
      ],
    ),
  );
  if (accepted ?? false) {
    await ref.read(appLockProvider.notifier).enable();
  }
}

/// The lock a restored session meets on a cold start when fingerprint
/// unlock is on. The prompt opens by itself; the password stays one tap
/// away for a sensor that fails.
class AppLockScreen extends ConsumerStatefulWidget {
  /// Creates the lock screen.
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_unlock()));
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(appLockProvider.notifier).unlock();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Scaffold(
      key: const Key('appLock.screen'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.fingerprint_rounded,
                  size: AppSizes.iconStateLg,
                  color: tokens.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'ضع بصمتك للدخول',
                  style: context.text.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const Key('appLock.unlock'),
                  onPressed: _busy ? null : () => unawaited(_unlock()),
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('الدخول بالبصمة'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  key: const Key('appLock.usePassword'),
                  onPressed: () => unawaited(
                    ref.read(sessionControllerProvider.notifier).signOut(),
                  ),
                  child: const Text('الدخول بكلمة المرور'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The fingerprint switch in the account screen; hidden on a device (or the
/// web build) that cannot use it.
class BiometricUnlockRow extends ConsumerWidget {
  /// Creates the row.
  const BiometricUnlockRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BiometricSetting? setting = ref.watch(biometricSettingProvider).value;
    if (setting == null || !setting.available) {
      return const SizedBox.shrink();
    }
    final AppTokens tokens = context.tokens;
    return SwitchListTile(
      key: const Key('account.biometricToggle'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      secondary: Icon(
        Icons.fingerprint_rounded,
        color: tokens.primary,
        size: AppSizes.iconLg,
      ),
      activeThumbColor: tokens.primary,
      title: Text(
        'الدخول بالبصمة',
        style: context.text.bodyLarge?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      value: setting.enabled,
      onChanged: (on) async {
        final AppLockController lock = ref.read(appLockProvider.notifier);
        if (on) {
          await lock.enable();
        } else {
          await lock.disable();
        }
        ref.invalidate(biometricSettingProvider);
      },
    );
  }
}
