/// The invitation page (migration 0073): the caller's fixed code and link,
/// the month's and the season's invitation points, how they count, and the
/// field where a new account names the friend who invited it.
///
/// Invitation points are never added to prediction points: they only break
/// a tie -- the month's points on the monthly board, the season's total on
/// the season board. The server decides everything; this page only draws
/// and sends.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/auth/install_id.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/providers.dart';
import '../competition/widgets/async_list_view.dart';
import 'referral_notice.dart';

/// CI's NUKHBA_INVITE_BASE_URL: the Northflank web mirror, which opens in
/// Yemen, where github.io is blocked. Empty when not set.
const String _inviteBaseFromBuild = String.fromEnvironment(
  'NUKHBA_INVITE_BASE_URL',
);

/// The web app's address; an invitation link opens it with `?ref=`.
/// GitHub Pages unless the build names another host.
const String inviteWebBase = _inviteBaseFromBuild == ''
    ? 'https://adbrhman.github.io/nukhbaa/'
    : _inviteBaseFromBuild;

/// The invitation link that carries [code].
String inviteLinkFor(String code) => '$inviteWebBase?ref=$code';

/// The invitation code the app was opened with (`?ref=` on the web), or an
/// empty string when there is none or it is not code-shaped.
String referralCodeFromLaunchUrl() {
  final String code = (Uri.base.queryParameters['ref'] ?? '')
      .trim()
      .toUpperCase();
  return RegExp(r'^[A-Z0-9]{4,32}$').hasMatch(code) ? code : '';
}

/// The sentence shown for a claim [status] from `POST /me/referral/claim`.
String referralClaimMessage(String status) => switch (status) {
  'claimed' =>
    'تم ربط حسابك بصاحب الدعوة. تُحتسب له النقطة بعد أول توقع لك على '
        'مباراة تُحتسب.',
  'already_claimed' => 'حسابك مرتبط بصاحب دعوة من قبل، ولا يمكن تغييره.',
  'disabled' => 'نظام الدعوات غير مفعّل حالياً.',
  'invalid_code' || 'unknown_code' => 'الرمز غير صحيح. تأكد منه وحاول مجدداً.',
  'self_referral' => 'لا يمكنك استخدام رمزك أنت.',
  'window_closed' => 'رمز الدعوة يُقبل خلال 24 ساعة من إنشاء الحساب فقط.',
  'app_required' => referralAppRequiredMessage,
  'same_device' => referralSameDeviceMessage,
  _ => 'تعذّر تأكيد الرمز. حاول مجدداً.',
};

/// `GET /me/referral` -- the caller's code and counters.
final myReferralProvider = FutureProvider.autoDispose<ReferralSummaryDto>((
  ref,
) async {
  final api = ref.watch(authApiProvider);
  final String? installId = await ref.read(installIdStoreProvider).read();
  return switch (await api.myReferral(installId: installId)) {
    Ok<ReferralSummaryDto>(:final value) => value,
    Err<ReferralSummaryDto>(:final error) => throw error,
  };
});

/// The invitation page.
class InviteFriendsScreen extends ConsumerStatefulWidget {
  /// Creates the page.
  const InviteFriendsScreen({super.key});

  @override
  ConsumerState<InviteFriendsScreen> createState() =>
      _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends ConsumerState<InviteFriendsScreen> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _claimMessage;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _claim() async {
    final String code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _claimMessage = referralClaimMessage('invalid_code'));
      return;
    }
    setState(() {
      _busy = true;
      _claimMessage = null;
    });
    final String? installId = await ref.read(installIdStoreProvider).read();
    final Result<ReferralStatusDto> result = await ref
        .read(authApiProvider)
        .claimReferral(code: code, installId: installId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _claimMessage = switch (result) {
        Ok<ReferralStatusDto>(:final value) => referralClaimMessage(
          value.status,
        ),
        Err<ReferralStatusDto>(:final error) => ErrorPresenter.message(error),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Scaffold(
      key: const Key('invite.screen'),
      backgroundColor: tokens.background,
      appBar: AppBar(centerTitle: true, title: const Text('ادعُ أصدقاءك')),
      body: AsyncObjectView<ReferralSummaryDto>(
        value: ref.watch(myReferralProvider),
        onRetry: () => ref.invalidate(myReferralProvider),
        builder: (context, summary) => ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            _Section(
              children: <Widget>[
                Text(
                  'رمز دعوتك',
                  textAlign: TextAlign.center,
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  summary.code,
                  key: const Key('invite.code'),
                  textAlign: TextAlign.center,
                  style: context.text.headlineMedium?.copyWith(
                    color: tokens.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('invite.copyLink'),
                        onPressed: () => unawaited(
                          _copy(
                            inviteLinkFor(summary.code),
                            'نُسخ رابط الدعوة',
                          ),
                        ),
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('نسخ الرابط'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('invite.copyCode'),
                        onPressed: () =>
                            unawaited(_copy(summary.code, 'نُسخ الرمز')),
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('نسخ الرمز'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Section(
              children: <Widget>[
                _Stat(
                  key: const Key('invite.monthPoints'),
                  label: 'نقاط الدعوة هذا الشهر',
                  value: '${summary.monthPoints} من ${summary.monthCap}',
                ),
                _Stat(
                  key: const Key('invite.seasonPoints'),
                  label: 'نقاط الدعوة هذا الموسم',
                  value: '${summary.seasonPoints}',
                ),
                _Stat(
                  key: const Key('invite.invited'),
                  label: 'سجّلوا برمزك',
                  value: '${summary.invitedCount}',
                ),
                _Stat(
                  key: const Key('invite.pending'),
                  label: 'بانتظار أول مباراة أو المراجعة',
                  value: '${summary.pendingCount}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Section(
              key: const Key('invite.rules'),
              children: <Widget>[
                Text(
                  'كيف تُحتسب؟',
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final String line in _rules)
                  Text(
                    '• $line',
                    style: context.text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Section(
              children: <Widget>[
                Text(
                  'هل دعاك صديق؟',
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'اكتب رمزه خلال 24 ساعة من إنشاء حسابك.',
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
                TextField(
                  key: const Key('invite.claimField'),
                  controller: _code,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_claim()),
                  decoration: const InputDecoration(labelText: 'رمز الدعوة'),
                ),
                FilledButton.tonal(
                  key: const Key('invite.claimButton'),
                  onPressed: _busy ? null : () => unawaited(_claim()),
                  child: const Text('تأكيد الرمز'),
                ),
                if (_claimMessage case final String message)
                  Text(
                    message,
                    key: const Key('invite.claimMessage'),
                    style: context.text.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const List<String> _rules = <String>[
  'كل صديق يسجّل برمزك ثم يتوقع مباراة تُحتسب يمنحك نقطة دعوة.',
  'نقاط الدعوة لا تُضاف إلى نقاط توقعاتك، وتُستخدم فقط عند تساوي النقاط.',
  'في ترتيب الشهر: يتقدم صاحب نقاط دعوة الشهر الأكثر، حتى 20 نقطة، وتبدأ من '
      'الصفر مع كل شهر.',
  'في ترتيب الموسم: يُحسم التعادل بمجموع نقاط الدعوة طوال الموسم.',
  'التسجيل وحده لا يمنح نقطة، والحسابات المشبوهة تُراجع قبل احتسابها.',
];

class _Section extends StatelessWidget {
  const _Section({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < children.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: context.text.titleMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
