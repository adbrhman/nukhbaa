/// Optional fingerprint sign-in: a user who switched it on signs back in
/// with a fingerprint after signing out, instead of typing the password.
///
/// It never stands between a live session and the app. The session
/// persists through the refresh token, so reopening the app -- after
/// closing it or clearing it from recents -- lands straight in it. The
/// fingerprint is met only on the sign-in screen after an explicit sign-out,
/// where [fingerprintSignInProvider] offers it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/biometric_unlock.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';

/// Switches fingerprint sign-in on and off. It holds no state: whether it
/// is on is read from [biometricPreferenceStoreProvider] where needed.
final appLockProvider = NotifierProvider<AppLockController, void>(
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

/// Whether the sign-in screen offers the fingerprint: unlock is on, a
/// refresh token was kept across the sign-out, and the device can prompt.
final fingerprintSignInProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final BiometricPreferenceStore prefs = ref.read(
      biometricPreferenceStoreProvider,
    );
    if (!await prefs.isEnabled()) return false;
    final String? kept = await prefs.readSavedRefreshToken();
    if (kept == null || kept.isEmpty) return false;
    return await ref.read(biometricAuthenticatorProvider).isAvailable();
  } on Object {
    return false;
  }
});

/// Switches fingerprint sign-in on and off.
class AppLockController extends Notifier<void> {
  @override
  void build() {}

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
    return true;
  }

  /// Switches fingerprint unlock off.
  Future<void> disable() async {
    // Off means off: nothing is kept for a fingerprint sign-in either.
    await ref.read(biometricPreferenceStoreProvider).clearSavedRefreshToken();
    await ref.read(biometricPreferenceStoreProvider).setEnabled(enabled: false);
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
        'بعد تسجيل الخروج، ادخل ببصمتك بدل كلمة المرور. '
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
