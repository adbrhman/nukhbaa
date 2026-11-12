/// اطلاع الدعم على توقعات اللاعب القادمة من محادثته (السكربت 261-262،
/// قرار المالك 2026-11-11): الاطلاع الوحيد على توقع قبل انطلاق مباراته.
/// يُطلب سبب، ويُسجَّل الاطلاع، وتصل اللاعب رسالة في المحادثة نفسها.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/format/timestamps.dart';
import '../../../core/ui/app_button.dart';

/// The longest reason the server keeps.
const int supportPeekReasonMaxLength = 200;

/// Asks the admin why he reads the player's open predictions, telling him
/// first that the player will be told. Null when he cancels.
Future<String?> askSupportPeekReason(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _ReasonDialog());

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String typed = _reason.text.trim();
    return AlertDialog(
      title: const Text('الاطلاع على توقعاته القادمة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'لا يطّلع أحد على توقع قبل انطلاق مباراته، إلا الدعم من '
              'محادثة اللاعب لمتابعة طلبه. ستصله رسالة في هذه المحادثة '
              'بأنك اطّلعت على توقعاته، ويُسجَّل الاطلاع وسببه.',
              key: Key('admin.support.peek.notice'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('admin.support.peek.reason'),
              controller: _reason,
              maxLength: supportPeekReasonMaxLength,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'السبب',
                hintText: 'مثل: يقول إن توقعه لم يُحفظ',
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      actions: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppButton(
              key: const Key('admin.support.peek.confirm'),
              label: 'اطّلع وأبلغ اللاعب',
              size: AppButtonSize.medium,
              onPressed: typed.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(typed),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('admin.support.peek.cancel'),
              label: 'إلغاء',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shows what support read: the player's predictions of the matches not
/// yet started, by kickoff.
Future<void> showSupportPeekedPredictions(
  BuildContext context,
  SupportPredictionsPeekDto peek,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (BuildContext sheet) {
    final AppTokens tokens = sheet.tokens;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.8,
        ),
        child: ListView(
          key: const Key('admin.support.peek.list'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: <Widget>[
            Text(
              'توقعاته للمباريات التي لم تبدأ',
              style: sheet.text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'أُبلغ اللاعب في المحادثة، وسُجّل الاطلاع.',
              style: sheet.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (peek.predictions.isEmpty)
              Text(
                'لا توقعات له لمباريات لم تبدأ.',
                key: const Key('admin.support.peek.empty'),
                style: sheet.text.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
            for (final SupportPeekedPredictionDto p in peek.predictions)
              _PeekedLine(
                key: Key('admin.support.peek.line.${p.fixtureId}'),
                line: p,
              ),
          ],
        ),
      ),
    );
  },
);

class _PeekedLine extends StatelessWidget {
  const _PeekedLine({super.key, required this.line});

  final SupportPeekedPredictionDto line;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String? league = line.leagueName;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${line.homeTeam} - ${line.awayTeam}',
              style: context.text.bodyLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              <String>[
                if (league != null) league,
                formatDayAndTime(context, line.kickoffAt),
              ].join(' · '),
              style: context.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'توقعه: ${line.homeGoals}-${line.awayGoals}'
              '${line.isDouble ? ' · دبل' : ''}',
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
