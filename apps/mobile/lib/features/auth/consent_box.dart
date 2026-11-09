/// The consent line of sign-up and of the first Google sign-in (script 224).
///
/// Google Play's user-generated-content policy asks the app to require users
/// to accept terms that forbid objectionable content *before* they create
/// any, and the app serves adults only (the rules and privacy pages say 18+).
/// One tick therefore covers the rules, the privacy policy and the age; the
/// two links beside it open the pages the tick refers to.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import 'rules_screen.dart';

/// The privacy policy, the page the Play listing also points to.
const String privacyPolicyUrl = 'https://nukhbaa.app/privacy/';

/// What the consent line says the person agrees to.
const String consentText =
    'أوافق على قواعد اللعب وسياسة الخصوصية، '
    'وأقرّ أن عمري 18 سنة أو أكثر، '
    'وألتزم بعدم نشر أي محتوى مسيء أو مخالف.';

/// The line under the box when the person tries to go on without ticking.
const String consentRequiredMessage =
    'لا يمكن المتابعة قبل الموافقة على القواعد والخصوصية وتأكيد السن';

/// Opens a web page outside the app; overridden in tests.
final Provider<Future<void> Function(Uri)> legalLinkOpenerProvider =
    Provider<Future<void> Function(Uri)>(
      (ref) => (Uri uri) async {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );

/// The tick box with the two links under it.
class ConsentBox extends ConsumerWidget {
  /// Creates the box.
  const ConsentBox({
    super.key,
    required this.checked,
    required this.enabled,
    required this.onChanged,
    this.errorText,
  });

  /// Whether the person has ticked it.
  final bool checked;

  /// False while a request is in flight.
  final bool enabled;

  /// Called with the new value when the box is tapped.
  final ValueChanged<bool> onChanged;

  /// The refusal shown under the box, if the person tried to go on without it.
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final String? error = errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          checked: checked,
          child: InkWell(
            key: const Key('consent.box'),
            onTap: enabled ? () => onChanged(!checked) : null,
            borderRadius: AppRadius.brButton,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTouchTarget,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Icon(
                      checked
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: AppSizes.iconMd,
                      color: checked ? tokens.primary : tokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        consentText,
                        key: const Key('consent.text'),
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: <Widget>[
            TextButton(
              key: const Key('consent.rules'),
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RulesScreen()),
                ),
              ),
              child: const Text('قواعد اللعب'),
            ),
            TextButton(
              key: const Key('consent.privacy'),
              onPressed: () => unawaited(
                ref.read(legalLinkOpenerProvider)(Uri.parse(privacyPolicyUrl)),
              ),
              child: const Text('سياسة الخصوصية'),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              error,
              key: const Key('consent.error'),
              style: context.text.bodySmall?.copyWith(color: tokens.errorText),
            ),
          ),
      ],
    );
  }
}
