library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/app_text_field.dart';
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

  void _toggleMode() {
    ref.read(sessionControllerProvider.notifier).clearFailure();
    setState(() => _isRegister = !_isRegister);
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

    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;

    return Scaffold(
      backgroundColor: tokens.background,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: tokens.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.maxFormWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Header(),
                    const SizedBox(height: AppSpacing.xxl),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: AppRadius.brXxl,
                        border: Border.all(color: tokens.border),
                        boxShadow: tokens.shadowLg,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isRegister ? 'Create account' : 'Sign in',
                              key: const Key('signIn.title'),
                              textAlign: TextAlign.center,
                              style: text.headlineSmall?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _isRegister
                                  ? 'Create an account to start playing Nukhba.'
                                  : 'Sign in with your email and password to continue.',
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            if (failure != null) ...[
                              _ErrorBanner(
                                key: const Key('signIn.errorBanner'),
                                message: ErrorPresenter.message(failure),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                            AppTextField(
                              fieldKey: const Key('signIn.emailField'),
                              controller: _emailController,
                              enabled: !inFlight,
                              label: 'Email',
                              hint: 'you@example.com',
                              prefixIcon: Icons.mail_outline,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              validator: (String? value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Please enter your email.'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppTextField(
                              fieldKey: const Key('signIn.passwordField'),
                              controller: _passwordController,
                              enabled: !inFlight,
                              obscure: true,
                              label: 'Password',
                              prefixIcon: Icons.lock_outline,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(session),
                              validator: (String? value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Please enter your password.'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            AppButton(
                              key: const Key('signIn.submit'),
                              label: _isRegister ? 'Create account' : 'Sign in',
                              loading: inFlight,
                              onPressed: inFlight
                                  ? null
                                  : () => _submit(session),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            AppButton(
                              key: const Key('signIn.toggleMode'),
                              label: _isRegister
                                  ? 'Already have an account? Sign in'
                                  : "New here? Create an account",
                              variant: AppButtonVariant.text,
                              onPressed: inFlight ? null : _toggleMode,
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
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Column(
      children: [
        Container(
          height: AppSizes.brandMark,
          width: AppSizes.brandMark,
          decoration: BoxDecoration(
            gradient: tokens.primaryGradient,
            borderRadius: AppRadius.brXl,
            boxShadow: tokens.shadowMd,
          ),
          child: Icon(
            Icons.sports_soccer_rounded,
            color: tokens.onPrimary,
            size: AppSizes.iconXl,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Nukhba',
          style: text.headlineMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Football prediction platform',
          style: text.bodySmall?.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.errorContainer,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: tokens.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: tokens.error,
            size: AppSizes.iconMd,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: tokens.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
