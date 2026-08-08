library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_motion.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/app_text_field.dart';
import '../../l10n/app_localizations.dart';
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
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isRegister = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  void _setMode(bool toRegister) {
    if (_isRegister == toRegister) return;
    ref.read(sessionControllerProvider.notifier).clearFailure();
    _confirmPasswordController.clear();
    setState(() => _isRegister = toRegister);
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
    final AppLocalizations l10n = AppLocalizations.of(context);

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
                            _AuthModeTabs(
                              isRegister: _isRegister,
                              enabled: !inFlight,
                              onChanged: _setMode,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Text(
                              _isRegister ? l10n.createAccount : l10n.signIn,
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
                                  ? l10n.signUpSubtitle
                                  : l10n.signInSubtitle,
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            if (_isRegister) ...[
                              const _RulesBox(),
                              const SizedBox(height: AppSpacing.xl),
                            ],
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
                              label: l10n.email,
                              hint: l10n.emailHint,
                              prefixIcon: Icons.mail_outline,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              validator: (String? value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? l10n.emailRequired
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppTextField(
                              fieldKey: const Key('signIn.passwordField'),
                              controller: _passwordController,
                              enabled: !inFlight,
                              obscure: true,
                              label: l10n.password,
                              prefixIcon: Icons.lock_outline,
                              textInputAction: _isRegister
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              autofillHints: [
                                _isRegister
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              onFieldSubmitted: _isRegister
                                  ? null
                                  : (_) => _submit(session),
                              validator: (String? value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? l10n.passwordRequired
                                  : null,
                            ),
                            if (_isRegister) ...[
                              const SizedBox(height: AppSpacing.lg),
                              AppTextField(
                                fieldKey: const Key(
                                  'signIn.confirmPasswordField',
                                ),
                                controller: _confirmPasswordController,
                                enabled: !inFlight,
                                obscure: true,
                                label: l10n.confirmPassword,
                                prefixIcon: Icons.lock_outline,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                onFieldSubmitted: (_) => _submit(session),
                                validator: (String? value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return l10n.confirmPasswordRequired;
                                  }
                                  if (value != _passwordController.text) {
                                    return l10n.passwordMismatch;
                                  }
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xl),
                            AppButton(
                              key: const Key('signIn.submit'),
                              label: _isRegister
                                  ? l10n.createAccount
                                  : l10n.signIn,
                              loading: inFlight,
                              onPressed: inFlight
                                  ? null
                                  : () => _submit(session),
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

/// Segmented دخول/تسجيل switcher replacing the old link-style toggle button.
/// Ported from the legacy `.auth-tabs` markup; colors come entirely from
/// [AppTokens] so the new app's palette is unaffected.
class _AuthModeTabs extends StatelessWidget {
  const _AuthModeTabs({
    required this.isRegister,
    required this.enabled,
    required this.onChanged,
  });

  final bool isRegister;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      height: AppSizes.controlMd,
      padding: const EdgeInsets.all(AppSpacing.xs / 2),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthModeTab(
              fieldKey: const Key('signIn.tabLogin'),
              label: AppLocalizations.of(context).authTabSignIn,
              selected: !isRegister,
              enabled: enabled,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _AuthModeTab(
              fieldKey: const Key('signIn.tabRegister'),
              label: AppLocalizations.of(context).authTabRegister,
              selected: isRegister,
              enabled: enabled,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeTab extends StatelessWidget {
  const _AuthModeTab({
    required this.fieldKey,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Key fieldKey;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Material(
      key: fieldKey,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.brSm,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: AppMotion.tabSwitch,
          curve: AppMotion.standardCurve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tokens.primary : Colors.transparent,
            borderRadius: AppRadius.brSm,
          ),
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: selected ? tokens.onPrimary : tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// "كيف تلعب؟" explainer shown on the register tab — ported from the legacy
/// `.rules-box` markup with the platform's current scoring copy.
class _RulesBox extends StatelessWidget {
  const _RulesBox();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.checklist_rtl_rounded,
                size: AppSizes.iconMd,
                color: tokens.textPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.rulesTitle,
                style: text.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.rulesTagline,
            style: text.bodySmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          _RuleItem(
            icon: Icons.sports_soccer_rounded,
            iconColor: tokens.textSecondary,
            label: l10n.rulesPredictMajorLeagues,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RuleItem(
            icon: Icons.check_circle_rounded,
            iconColor: tokens.primary,
            label: l10n.rulesCorrectPrediction,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RuleItem(
            icon: Icons.cancel_rounded,
            iconColor: tokens.textMuted,
            label: l10n.rulesWrongPrediction,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RuleItem(
            icon: Icons.star_rounded,
            iconColor: tokens.gold,
            label: l10n.rulesDoubleMatch,
          ),
        ],
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppSizes.iconSm, color: iconColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: text.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final AppLocalizations l10n = AppLocalizations.of(context);
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
          l10n.appTitle,
          style: text.headlineMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.tagline,
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
