/// The session-driven router for the app's top level.
///
/// v1 routing is deliberately minimal (Flutter App phase §4: "sign-in screen
/// if no persisted token, otherwise the home screen") and needs no routing
/// package — none is ratified in §3, and a URL-addressable router is a concern
/// of the later multi-screen slices, not the Auth slice. This widget simply
/// switches on the [SessionController]'s [SessionState]:
///   * still resolving a persisted token at boot (loading / [SessionUnknown])
///     → a splash;
///   * [SessionAuthenticated] → the Nukhbaa navigation shell, carrying the
///     verified principal;
///   * every other state (unauthenticated / authenticating / failed) → the
///     [SignInScreen], which itself renders progress and any typed failure.
///
/// Because the gate watches the same async provider the controller drives,
/// sign-in / sign-out / restore transitions re-route automatically with no
/// imperative navigation.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/error/error_presenter.dart';
import '../../core/session/session_scope.dart';

import 'app_lock.dart';
import 'name_setup_screen.dart';
import 'nukhbaa_shell.dart';
import 'session_controller.dart';
import 'session_state.dart';
import 'sign_in_screen.dart';

/// Chooses the top-level screen from the current authentication session.
class SessionGate extends ConsumerWidget {
  /// Creates the session gate.
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSession = ref.watch(sessionControllerProvider);
    // Watched from the first frame, so the lock sees every sign-out.
    final AppLockState lock = ref.watch(appLockProvider);

    // A session that ends while the user is deep inside a pushed route (a
    // leaderboard, the admin panel, an open dialog) used to leave them
    // exactly there: only `home:` swapped underneath, while every request on
    // the visible screen quietly 401'd. Unwind to the root so what they
    // actually see is the sign-in form.
    ref.listen<AsyncValue<SessionState>>(sessionControllerProvider, (
      previous,
      next,
    ) {
      // A sign-in that just succeeded (password or registration): offer
      // fingerprint unlock once, over the freshly opened app.
      if (previous?.value is SessionAuthenticating &&
          next.value is SessionAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) unawaited(offerBiometricUnlock(context, ref));
        });
      }
      if (previous?.value is! SessionAuthenticated) return;
      if (next.value is SessionAuthenticated) return;
      final NavigatorState navigator = Navigator.of(context);
      final bool signedOut = next.value is SessionUnauthenticated;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) {
          navigator.popUntil((Route<dynamic> route) => route.isFirst);
        }
        // Signed out (by choice or by an expired session): everything cached
        // belonged to the account that just left, so the next one starts from
        // a fresh container instead of seeing that account's predictions.
        if (signedOut && context.mounted) {
          SessionScope.maybeOf(context)?.reset();
        }
      });
    });

    // The boot-time restore is in flight (or errored at the provider level,
    // which cannot happen here since build() is total): show a splash rather
    // than flashing the sign-in form to a returning, still-valid user.
    if (asyncSession.isLoading) {
      return const _Splash();
    }

    final session = asyncSession.value ?? const SessionUnauthenticated();
    return switch (session) {
      SessionUnknown() => const _Splash(),
      SessionAuthenticated(:final user) => switch (lock) {
        AppLockState.checking => const _Splash(),
        AppLockState.locked => const AppLockScreen(),
        // An account that never chose a name (a first Google sign-in)
        // chooses it before anything else, as registration would have.
        AppLockState.open =>
          hasAutomaticDisplayName(user)
              ? NameSetupScreen(user: user)
              : NukhbaaShell(user: user),
      },
      // Still holding a token the server never rejected: offline, not signed
      // out. Dropping such a user onto the password form was the bug.
      SessionFailed(canRetryRestore: true, :final error) => _ConnectionRetry(
        error: error,
      ),
      SessionUnauthenticated() ||
      SessionAuthenticating() ||
      SessionFailed() => const SignInScreen(),
    };
  }
}

/// Shown when a session that is still held could not be confirmed with the
/// server -- in practice a launch with no connectivity. The token stays on
/// disk, so this is a retry affordance, never a sign-out.
class _ConnectionRetry extends ConsumerWidget {
  const _ConnectionRetry({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: const Key('session.connectionRetry'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                ErrorPresenter.message(error),
                key: const Key('session.connectionRetry.message'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('session.connectionRetry.button'),
                onPressed: () => unawaited(
                  ref.read(sessionControllerProvider.notifier).retry(),
                ),
                child: const Text('إعادة المحاولة'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('session.connectionRetry.signOut'),
                onPressed: () => unawaited(
                  ref.read(sessionControllerProvider.notifier).signOut(),
                ),
                child: const Text(
                  'تسجيل الدخول '
                  'بحساب آخر',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A minimal boot splash shown while the persisted session is being resolved.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: Key('session.splash'),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
