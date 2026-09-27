/// لوحة المشرف لنظام الدعوات (migration 0075): زر التشغيل والإيقاف،
/// أعداد الدعوات حسب الحالة، كل دعوة مع حالتها وسببها، وأصحاب الروابط.
/// القرارات (قبول، رفض، سحب) تُرسل بسبب إلزامي، والخادم وحده يقرر.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// `GET /admin/referral-overview`.
final adminReferralOverviewProvider =
    FutureProvider.autoDispose<AdminReferralOverviewDto>((ref) async {
      return switch (await ref.watch(adminApiProvider).referralOverview()) {
        Ok<AdminReferralOverviewDto>(:final value) => value,
        Err<AdminReferralOverviewDto>(:final error) => throw error,
      };
    });

/// The states in the order the page lists them.
const List<String> referralStates = <String>[
  'held',
  'pending',
  'paid',
  'revoked',
  'rejected',
];

/// The Arabic name of an invitation [state].
String referralStateLabel(String state) => switch (state) {
  'pending' => 'بانتظار أول مباراة',
  'held' => 'محجوزة للمراجعة',
  'paid' => 'محتسبة',
  'revoked' => 'مسحوبة',
  'rejected' => 'مرفوضة',
  _ => state,
};

/// The Arabic wording of a hold or revoke [reason].
String referralReasonLabel(String reason) => switch (reason) {
  'shared_network' => 'نفس الشبكة مع مدعو آخر',
  'shared_install' => 'نفس الجهاز مع مدعو آخر',
  'inviter_install' => 'على جهاز صاحب الرابط',
  'burst' => 'دعوات كثيرة لنفس الشخص في يوم',
  'inactive_7_days' => 'خمول 7 أيام بلا توقعات',
  _ => reason,
};

String _decisionMessage(String status) => switch (status) {
  'approved' => 'تم قبول الدعوة واحتسابها',
  'rejected' => 'تم رفض الدعوة',
  'revoked' => 'تم سحب النقطة',
  'not_held' => 'الدعوة ليست محجوزة',
  'not_paid' => 'الدعوة غير محتسبة',
  'already_decided' => 'تم البت في هذه الدعوة من قبل',
  'unknown_invitation' => 'الدعوة غير موجودة',
  _ => status,
};

/// The invitation system section of the admin hub.
class ReferralAdminSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const ReferralAdminSection({super.key});

  @override
  ConsumerState<ReferralAdminSection> createState() =>
      _ReferralAdminSectionState();
}

class _ReferralAdminSectionState extends ConsumerState<ReferralAdminSection> {
  String _filter = 'all';
  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _busy = true);
    final Result<ReferralSwitchDto> result = await ref
        .read(adminApiProvider)
        .setReferralsEnabled(enabled: enabled);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(switch (result) {
      Ok<ReferralSwitchDto>(:final value) =>
        value.enabled ? 'تم تشغيل نظام الدعوات' : 'تم إيقاف نظام الدعوات',
      Err<ReferralSwitchDto>(:final error) => ErrorPresenter.message(error),
    });
    ref.invalidate(adminReferralOverviewProvider);
  }

  Future<void> _decide(
    ReferralInvitationDto invitation,
    String decision,
  ) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(decision: decision),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final Result<ReferralStatusDto> result = await ref
        .read(adminApiProvider)
        .reviewReferral(
          inviteeId: invitation.inviteeId,
          decision: decision,
          reason: reason,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(switch (result) {
      Ok<ReferralStatusDto>(:final value) => _decisionMessage(value.status),
      Err<ReferralStatusDto>(:final error) => ErrorPresenter.message(error),
    });
    ref.invalidate(adminReferralOverviewProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AdminReferralOverviewDto> overview = ref.watch(
      adminReferralOverviewProvider,
    );
    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              error is AppError
                  ? ErrorPresenter.message(error)
                  : 'تعذّر تحميل نظام الدعوات',
              key: const Key('admin.referrals.error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => ref.invalidate(adminReferralOverviewProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
      data: (AdminReferralOverviewDto data) => _body(context, data),
    );
  }

  Widget _body(BuildContext context, AdminReferralOverviewDto data) {
    final AppTokens tokens = context.tokens;
    final List<ReferralInvitationDto> shown = <ReferralInvitationDto>[
      for (final ReferralInvitationDto i in data.invitations)
        if (_filter == 'all' || i.state == _filter) i,
    ];
    return ListView(
      key: const Key('admin.referrals.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'نظام الدعوات',
          subtitle:
              'نقاط الدعوة لا تُضاف إلى نقاط التوقعات، وتكسر التعادل فقط.',
        ),
        AdminCard(
          padding: EdgeInsets.zero,
          // A ListTile paints its ink on the nearest Material; the card's own
          // background would hide it, so the tile gets a Material of its own.
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const Key('admin.referrals.switch'),
              value: data.enabled,
              onChanged: _busy ? null : (bool v) => unawaited(_toggle(v)),
              title: const Text('تشغيل نظام الدعوات'),
              subtitle: Text(
                data.enabled
                    ? 'يعمل: تُقبل الرموز وتُحتسب النقاط وتُسحب من الخاملين.'
                    : 'متوقف: لا تُقبل رموز، ولا تُحتسب أو تُسحب نقاط. '
                          'النقاط المحتسبة تبقى كما هي.',
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final String state in referralStates)
              Chip(
                key: Key('admin.referrals.count.$state'),
                label: Text(
                  '${referralStateLabel(state)}: ${data.stateCounts[state] ?? 0}',
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'الدعوات',
          style: context.text.titleSmall?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final String state in <String>['all', ...referralStates])
              ChoiceChip(
                key: Key('admin.referrals.filter.$state'),
                label: Text(
                  state == 'all' ? 'الكل' : referralStateLabel(state),
                ),
                selected: _filter == state,
                onSelected: (_) => setState(() => _filter = state),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('لا توجد دعوات هنا', textAlign: TextAlign.center),
          ),
        for (final ReferralInvitationDto i in shown) ...<Widget>[
          _InvitationCard(
            invitation: i,
            busy: _busy,
            onDecide: (String decision) => unawaited(_decide(i, decision)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          'أصحاب الروابط',
          style: context.text.titleSmall?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (data.referrers.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('لم يدعُ أحد بعد', textAlign: TextAlign.center),
          ),
        for (final ReferrerTotalsDto r in data.referrers) ...<Widget>[
          AdminCard(
            key: Key('admin.referrals.referrer.${r.referrerId}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  r.referrerName,
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'دعا ${r.invited} · محتسبة ${r.paid} · بانتظار ${r.pending} '
                  '· محجوزة ${r.held} · مسحوبة أو مرفوضة ${r.refused}',
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                Text(
                  'نقاط الدعوة هذا الشهر: ${r.monthPoints} من 20',
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.busy,
    required this.onDecide,
  });

  final ReferralInvitationDto invitation;
  final bool busy;
  final ValueChanged<String> onDecide;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final ReferralInvitationDto i = invitation;
    final Color stateColor = switch (i.state) {
      'paid' => tokens.success,
      'held' => tokens.gold,
      'revoked' || 'rejected' => tokens.error,
      _ => tokens.textSecondary,
    };
    final List<String> lines = <String>[
      'سجّل: ${formatTimestamp(context, i.claimedAt)}',
      if (i.lastPredictionAt case final String last)
        'آخر توقع: ${formatTimestamp(context, last)}'
      else
        'لم يتوقع بعد',
      if (i.holdReasons.isNotEmpty)
        'سبب الحجز: ${i.holdReasons.map(referralReasonLabel).join('، ')}',
      if (i.revokeReason case final String reason)
        'سبب السحب: ${referralReasonLabel(reason)}',
      if (i.inviteeStatus == 'suspended') 'الحساب موقوف',
    ];
    return AdminCard(
      key: Key('admin.referrals.invitation.${i.inviteeId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${i.inviteeName} ← ${i.referrerName}',
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                referralStateLabel(i.state),
                style: context.text.labelMedium?.copyWith(
                  color: stateColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final String line in lines)
            Text(
              line,
              style: context.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          if (i.state == 'held' || i.state == 'paid') ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                if (i.state == 'held') ...<Widget>[
                  FilledButton.tonal(
                    key: Key('admin.referrals.approve.${i.inviteeId}'),
                    onPressed: busy ? null : () => onDecide('approve'),
                    child: const Text('قبول'),
                  ),
                  OutlinedButton(
                    key: Key('admin.referrals.reject.${i.inviteeId}'),
                    onPressed: busy ? null : () => onDecide('reject'),
                    child: const Text('رفض'),
                  ),
                ],
                if (i.state == 'paid')
                  OutlinedButton(
                    key: Key('admin.referrals.revoke.${i.inviteeId}'),
                    onPressed: busy ? null : () => onDecide('revoke'),
                    child: const Text('سحب النقطة'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for the mandatory reason of a decision; pops the reason, or null.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.decision});

  final String decision;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final String text = _reason.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'اكتب سبباً من 3 أحرف على الأقل');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(switch (widget.decision) {
        'approve' => 'قبول الدعوة',
        'reject' => 'رفض الدعوة',
        _ => 'سحب النقطة',
      }),
      content: TextField(
        key: const Key('admin.referrals.reasonField'),
        controller: _reason,
        autofocus: true,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: 'السبب (إلزامي)',
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('admin.referrals.reasonConfirm'),
          onPressed: _confirm,
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}
