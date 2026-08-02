library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/error/error_presenter.dart';
import '../../core/theme/app_colors.dart';
import 'session_controller.dart';
import 'session_state.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _isRegister = false;
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit(SessionState current) {
    if (current is SessionAuthenticating) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    unawaited(
      _isRegister
          ? ref
                .read(sessionControllerProvider.notifier)
                .register(
                  email: _emailController.text.trim(),
                  password: _passwordController.text,
                )
          : ref
                .read(sessionControllerProvider.notifier)
                .signInWithCredentials(
                  email: _emailController.text.trim(),
                  password: _passwordController.text,
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SessionState> asyncSession = ref.watch(
      sessionControllerProvider,
    );
    final SessionState session = asyncSession.value ?? const SessionUnknown();
    final bool inFlight =
        asyncSession.isLoading || session is SessionAuthenticating;
    final AppError? failure = session is SessionFailed ? session.error : null;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const _Header(),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppColors.border),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              _isRegister ? 'Create account' : 'Sign in',
                              key: const Key('signIn.title'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isRegister
                                  ? 'Create an account to start playing Nukhba.'
                                  : 'Sign in with your email and password to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (failure != null) ...<Widget>[
                              _ErrorBanner(
                                key: const Key('signIn.errorBanner'),
                                message: ErrorPresenter.message(failure),
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              key: const Key('signIn.emailField'),
                              controller: _emailController,
                              enabled: !inFlight,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(
                                  Icons.mail_outline,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              validator: (String? value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Please enter your email.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const Key('signIn.passwordField'),
                              controller: _passwordController,
                              enabled: !inFlight,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: AppColors.textMuted,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppColors.textMuted,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (String? value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Please enter your password.'
                                  : null,
                              onFieldSubmitted: (_) => _submit(session),
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              key: const Key('signIn.submit'),
                              onPressed: inFlight
                                  ? null
                                  : () => _submit(session),
                              child: inFlight
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.onPrimary,
                                      ),
                                    )
                                  : Text(
                                      _isRegister
                                          ? 'Create account'
                                          : 'Sign in',
                                    ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              key: const Key('signIn.toggleMode'),
                              onPressed: inFlight
                                  ? null
                                  : () {
                                      ref
                                          .read(
                                            sessionControllerProvider.notifier,
                                          )
                                          .clearFailure();
                                      setState(
                                        () => _isRegister = !_isRegister,
                                      );
                                    },
                              child: Text(
                                _isRegister
                                    ? 'Already have an account? Sign in'
                                    : "New here? Create an account",
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.sports_soccer,
            color: AppColors.onPrimary,
            size: 40,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Nukhba',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Football prediction platform',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
