import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/platform/browser_url.dart';
import '../../core/platform/reset_url.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/providers.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/app_text_field.dart';
import '../../l10n/app_localizations.dart';
import 'password_reset_texts.dart';
import 'session_gate.dart';

/// Password recovery screen.
///
/// Without [recoveryToken] it sends the recovery email, then takes the code
/// that email carries and trades it for a recovery token (batch 110), so the
/// player never leaves the app. With a token it sets a new password.
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.recoveryToken, this.initialEmail});

  final String? recoveryToken;
  final String? initialEmail;

  bool get isReset => recoveryToken != null && recoveryToken!.isNotEmpty;

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _confirmController = TextEditingController();

  final TextEditingController _codeController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = false;
  AppError? _failure;
  bool _sent = false;
  bool _updated = false;
  bool _resent = false;
  bool _canResend = false;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// The e-mail service refuses a new code for a minute after the last one.
  void _startResendCooldown() {
    _resendTimer?.cancel();
    _canResend = false;
    _resendTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) setState(() => _canResend = true);
    });
  }

  Future<void> _verifyCode() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _loading = true;
      _failure = null;
      _resent = false;
    });

    final Result<PasswordResetCodeResponseDto> result = await ref
        .read(authApiProvider)
        .verifyPasswordResetCode(
          email: _emailController.text.trim(),
          code: _codeController.text.trim(),
        );

    if (!mounted) return;

    switch (result) {
      case Ok<PasswordResetCodeResponseDto>(:final value):
        unawaited(
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) =>
                  PasswordResetScreen(recoveryToken: value.recoveryToken),
            ),
          ),
        );

      case Err<PasswordResetCodeResponseDto>(:final error):
        setState(() {
          _loading = false;
          _failure = error;
        });
    }
  }

  Future<void> _resend() async {
    if (_loading || !_canResend) return;

    setState(() {
      _loading = true;
      _failure = null;
      _resent = false;
    });

    final Result<PasswordResetResponseDto> result = await ref
        .read(authApiProvider)
        .requestPasswordReset(email: _emailController.text.trim());

    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Ok<PasswordResetResponseDto>():
          _resent = true;
          _codeController.clear();
          _startResendCooldown();
        case Err<PasswordResetResponseDto>(:final error):
          _failure = error;
      }
    });
  }

  void _changeEmail() {
    _resendTimer?.cancel();
    setState(() {
      _sent = false;
      _resent = false;
      _failure = null;
      _codeController.clear();
    });
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _loading = true;
      _failure = null;
    });

    final api = ref.read(authApiProvider);

    final Result<PasswordResetResponseDto> result = widget.isReset
        ? await api.updatePassword(
            recoveryToken: widget.recoveryToken!,
            password: _passwordController.text,
          )
        : await api.requestPasswordReset(email: _emailController.text.trim());

    if (!mounted) return;

    switch (result) {
      case Ok<PasswordResetResponseDto>():
        setState(() {
          _loading = false;

          if (widget.isReset) {
            _updated = true;
          } else {
            _sent = true;
            _startResendCooldown();
          }
        });

      case Err<PasswordResetResponseDto>(:final error):
        setState(() {
          _loading = false;
          _failure = error;
        });
    }
  }

  void _backToSignIn() {
    if (widget.isReset) {
      clearPasswordResetUrl();
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SessionGate()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = context.text;
    final l10n = AppLocalizations.of(context);

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
                child: Container(
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
                        Icon(
                          widget.isReset
                              ? Icons.lock_reset_rounded
                              : Icons.mark_email_unread_outlined,
                          size: 48,
                          color: tokens.primary,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          widget.isReset
                              ? l10n.resetPasswordTitle
                              : l10n.forgotPasswordTitle,
                          textAlign: TextAlign.center,
                          style: text.headlineSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          widget.isReset
                              ? l10n.resetPasswordSubtitle
                              : _sent
                              ? resetCodeSentMessage(
                                  _emailController.text.trim(),
                                )
                              : resetCodeRequestSubtitle,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        if (_failure != null) ...[
                          Text(
                            ErrorPresenter.message(_failure!),
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: tokens.error,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        if (_resent && _failure == null) ...[
                          Text(
                            resetCodeResentMessage,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: tokens.primary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        if (_updated)
                          _SuccessPanel(
                            message: l10n.passwordResetSuccess,
                            buttonLabel: l10n.backToSignIn,
                            onPressed: _backToSignIn,
                          )
                        else if (_sent) ...[
                          AppTextField(
                            fieldKey: const Key('passwordReset.codeField'),
                            controller: _codeController,
                            enabled: !_loading,
                            label: resetCodeFieldLabel,
                            hint: resetCodeFieldHint,
                            prefixIcon: Icons.pin_outlined,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            onFieldSubmitted: (_) => unawaited(_verifyCode()),
                            validator: (value) =>
                                RegExp(r'^\d{6,10}$').hasMatch(value ?? '')
                                ? null
                                : resetCodeFormatError,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          AppButton(
                            key: const Key('passwordReset.verify'),
                            label: resetCodeVerifyLabel,
                            onPressed: _loading
                                ? null
                                : () => unawaited(_verifyCode()),
                            loading: _loading,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            key: const Key('passwordReset.resend'),
                            label: _canResend
                                ? resetCodeResendLabel
                                : resetCodeResendWaitLabel,
                            variant: AppButtonVariant.text,
                            size: AppButtonSize.medium,
                            onPressed: _loading || !_canResend
                                ? null
                                : () => unawaited(_resend()),
                          ),
                          AppButton(
                            key: const Key('passwordReset.changeEmail'),
                            label: resetCodeChangeEmailLabel,
                            variant: AppButtonVariant.text,
                            size: AppButtonSize.medium,
                            onPressed: _loading ? null : _changeEmail,
                          ),
                          AppButton(
                            key: const Key('passwordReset.back'),
                            label: l10n.backToSignIn,
                            variant: AppButtonVariant.text,
                            size: AppButtonSize.medium,
                            onPressed: _loading ? null : _backToSignIn,
                          ),
                        ] else ...[
                          if (!widget.isReset)
                            AppTextField(
                              fieldKey: const Key('passwordReset.emailField'),
                              controller: _emailController,
                              enabled: !_loading,
                              label: l10n.email,
                              hint: l10n.emailHint,
                              prefixIcon: Icons.mail_outline,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.email],
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? l10n.emailRequired
                                  : null,
                            )
                          else ...[
                            AppTextField(
                              fieldKey: const Key(
                                'passwordReset.passwordField',
                              ),
                              controller: _passwordController,
                              enabled: !_loading,
                              obscure: true,
                              label: l10n.newPassword,
                              prefixIcon: Icons.lock_outline,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              validator: (value) =>
                                  value == null || value.length < 8
                                  ? l10n.passwordTooShort
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppTextField(
                              fieldKey: const Key('passwordReset.confirmField'),
                              controller: _confirmController,
                              enabled: !_loading,
                              obscure: true,
                              label: l10n.confirmNewPassword,
                              prefixIcon: Icons.lock_outline,
                              textInputAction: TextInputAction.done,
                              validator: (value) =>
                                  value != _passwordController.text
                                  ? l10n.passwordMismatch
                                  : null,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          AppButton(
                            key: const Key('passwordReset.submit'),
                            label: widget.isReset
                                ? l10n.saveNewPassword
                                : resetCodeSendLabel,
                            onPressed: _loading
                                ? null
                                : () => unawaited(_submit()),
                            loading: _loading,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          AppButton(
                            key: const Key('passwordReset.back'),
                            label: l10n.backToSignIn,
                            variant: AppButtonVariant.text,
                            size: AppButtonSize.medium,
                            onPressed: _loading ? null : _backToSignIn,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      children: [
        Icon(Icons.check_circle_outline, size: 48, color: tokens.primary),
        const SizedBox(height: AppSpacing.lg),
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.text.bodyLarge?.copyWith(color: tokens.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(label: buttonLabel, onPressed: onPressed),
      ],
    );
  }
}

/// Supabase recovery tokens are delivered in the URL fragment.
String? recoveryTokenFromWebUrl() {
  if (!kIsWeb) return null;

  final fragment = Uri.base.fragment;

  final match = RegExp(
    r'(?:^|[#?&])access_token=([^&#]+)',
  ).firstMatch(fragment);

  return match == null ? null : Uri.decodeComponent(match.group(1)!);
}

/// Whether the web app was opened by a password-reset link (audit M-02:
/// a sign-up confirmation link is not one).
bool isPasswordResetWebUrl() => kIsWeb && isPasswordResetUrl(Uri.base);
