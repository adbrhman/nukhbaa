/// The one-time choice of a display name, for an account that never made it
/// (a first Google sign-in): the name other players see in leaderboards and
/// groups. Mandatory, like the name field of registration; the only other
/// way out is signing out.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import 'consent_box.dart';
import 'session_controller.dart';

/// The longest display name the platform accepts (`User.maxDisplayNameLength`
/// in the domain, which this app does not import).
const int _maxDisplayNameLength = 60;

/// The name the database assigns when none was chosen (migration 0016's
/// `identity.default_display_name`): the email's local part, or `Player`.
String automaticDisplayNameOf(AuthenticatedUserDto user) {
  final String local = (user.email ?? '').split('@').first;
  return local.isEmpty ? 'Player' : local;
}

/// Whether [user] still carries the name the database assigned on its own,
/// i.e. never chose one.
bool hasAutomaticDisplayName(AuthenticatedUserDto user) =>
    user.displayName == automaticDisplayNameOf(user);

/// Whether [name] is a two-part name: at least two words of two letters or
/// more. The rule of `User.isTwoPartName` in the domain, which the server
/// applies to every new account (decided 2026-11-02); checked here first so
/// a one-word name is refused without a request.
bool isTwoPartDisplayName(String name) {
  final RegExp letter = RegExp(r'\p{L}', unicode: true);
  final int words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where(
        (String word) =>
            letter.allMatches(word.replaceAll('\u0640', '')).length >= 2,
      )
      .length;
  return words >= 2;
}

/// The line under the name field when the name is a single word.
const String twoPartNameMessage =
    'اكتب اسمك الأول واسم أبيك أو لقبك، مثل: محمد العماري';

/// Asks a user who never chose a display name to choose it, once.
class NameSetupScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [user].
  const NameSetupScreen({super.key, required this.user});

  /// The signed-in user whose name is still the automatic one.
  final AuthenticatedUserDto user;

  @override
  ConsumerState<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends ConsumerState<NameSetupScreen> {
  final TextEditingController _name = TextEditingController();

  /// The real family name, or the father's name (2026-11-03).
  final TextEditingController _family = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The consent (rules, privacy, 18+) of an account that never saw the
  /// sign-up form: asked before the name, so before any content (224).
  bool _consent = false;
  String? _consentError;

  @override
  void dispose() {
    _name.dispose();
    _family.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_consent) {
      setState(() => _consentError = consentRequiredMessage);
      return;
    }
    final String first = _name.text.trim();
    final String family = _family.text.trim();
    if (first.isEmpty || family.isEmpty) {
      setState(() => _error = 'اكتب اسمك الأول واسم عائلتك الحقيقيين');
      return;
    }
    final String name = '$first $family';
    if (name == automaticDisplayNameOf(widget.user)) {
      setState(
        () =>
            _error = 'اختر اسماً يعرفك به الآخرون، غير بداية بريدك الإلكتروني',
      );
      return;
    }
    if (!isTwoPartDisplayName(name)) {
      setState(() => _error = twoPartNameMessage);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<void> result = await ref
        .read(sessionControllerProvider.notifier)
        .chooseDisplayName(displayName: name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result case Err<void>(:final error)) {
        _error = ErrorPresenter.message(error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Scaffold(
      key: const Key('nameSetup.screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.badge_outlined,
                  size: AppSizes.iconStateLg,
                  color: tokens.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'اختر اسمك',
                  textAlign: TextAlign.center,
                  style: context.text.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'يجب إدخال الاسم الذي يعرفك به الآخرون في حياتك. '
                  'هذا الاسم يظهر للاعبين الآخرين في الترتيب والمجموعات، '
                  'ولا يمكن تغييره بعد الحفظ.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  key: const Key('nameSetup.field'),
                  controller: _name,
                  enabled: !_busy,
                  maxLength: _maxDisplayNameLength ~/ 2,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الأول الحقيقي',
                    hintText: 'مثال: محمد',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('nameSetup.familyField'),
                  controller: _family,
                  enabled: !_busy,
                  maxLength: _maxDisplayNameLength ~/ 2,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_save()),
                  decoration: InputDecoration(
                    labelText: 'اسم العائلة الحقيقي',
                    hintText: 'مثال: أحمد',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ConsentBox(
                  checked: _consent,
                  enabled: !_busy,
                  errorText: _consentError,
                  onChanged: (bool value) => setState(() {
                    _consent = value;
                    if (value) _consentError = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  key: const Key('nameSetup.save'),
                  onPressed: _busy ? null : () => unawaited(_save()),
                  child: const Text('حفظ والمتابعة'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  key: const Key('nameSetup.signOut'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          ref
                              .read(sessionControllerProvider.notifier)
                              .signOut(),
                        ),
                  child: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
