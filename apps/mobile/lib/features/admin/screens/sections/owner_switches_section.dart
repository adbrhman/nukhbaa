/// تبويب «المفاتيح» في «الإدارة العامة للمالك» (السكربت 289، البند 3 من
/// تقرير المالك، فوق الهجرة 0218): مفاتيح الطوارئ بيد المالكَين وحدهما،
/// أولها «تتويج الشهر» (القرار ق٠٤) الذي كان يُدار من محرر SQL.
///
/// كل مفتاح يظهر بحالته وآخر تغيير له: متى، ومن غيّره (أنت، أو المالك
/// الآخر، أو محرر SQL)، ولماذا. ولا يتغير مفتاح إلا بسبب مكتوب. يقرأ الخادم
/// المفتاح في كل دورة، فلا يحتاج التغيير إعادة نشر، ويُسجَّل الطلب في سجل
/// المالك. والخادم يجيب غير المالكَين بمسار غير موجود.
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
import '../../../../core/ui/app_button.dart';
import '../../widgets/admin_ui_kit.dart';

// NK289_10
/// `GET /owner/switches`.
final ownerSwitchesProvider = FutureProvider.autoDispose<OwnerSwitchesDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).ownerSwitches()) {
    Ok<OwnerSwitchesDto>(:final value) => value,
    Err<OwnerSwitchesDto>(:final error) => throw error,
  };
});

/// The longest reason the server keeps.
const int ownerSwitchReasonMaxLength = 200;

/// What the owner reads about one switch: its name, what it does on and
/// off, and what turning it each way will do.
typedef _SwitchText = ({
  String name,
  String whenOn,
  String whenOff,
  String turnOn,
  String turnOff,
});

_SwitchText _textOf(String key) => switch (key) {
  'crowning' => (
    name: 'تتويج الشهر',
    whenOn:
        'يعمل: يُتوَّج كل شهر تلقائياً بعد آخر مبارياته، ويستطيع المشرفون '
        'التتويج يدوياً.',
    whenOff:
        'موقوف: لا يُتوَّج أي شهر تلقائياً، ولا يتوّج المشرفون. تستطيع أنت '
        'التتويج يدوياً من «المسابقات الشهرية».',
    turnOn:
        'يعود التتويج التلقائي في دورته التالية خلال دقيقتين، فيُتوَّج كل '
        'شهر انتهت مبارياته، ويستطيع المشرفون التتويج. تأكد من صحة النقاط '
        'قبل التشغيل.',
    turnOff:
        'يتوقف التتويج التلقائي خلال دقيقتين، ويُرفض تتويج المشرفين. يصلك '
        'تنبيه مرة لكل شهر ينتظر، وتستطيع أنت التتويج يدوياً. لا يُلغى '
        'تتويج تم.',
  ),
  _ => (
    name: key,
    whenOn: 'يعمل',
    whenOff: 'موقوف',
    turnOn: 'يعود المفتاح إلى العمل.',
    turnOff: 'يتوقف المفتاح.',
  ),
};

String _byLabel(String? by) => switch (by) {
  OwnerSwitchDto.byYou => 'بواسطتك',
  OwnerSwitchDto.byOtherOwner => 'بواسطة المالك الآخر',
  OwnerSwitchDto.bySqlEditor => 'من محرر SQL',
  _ => '',
};

/// The owners' switches tab.
class OwnerSwitchesSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const OwnerSwitchesSection({super.key});

  @override
  ConsumerState<OwnerSwitchesSection> createState() =>
      _OwnerSwitchesSectionState();
}

class _OwnerSwitchesSectionState extends ConsumerState<OwnerSwitchesSection> {
  bool _busy = false;

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _turn(OwnerSwitchDto line, bool on) async {
    final _SwitchText text = _textOf(line.key);
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: on ? 'تشغيل «${text.name}»' : 'إيقاف «${text.name}»',
        notice: on ? text.turnOn : text.turnOff,
        confirmLabel: on ? 'شغّل' : 'أوقف',
        destructive: !on,
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final Result<OwnerSwitchDto> result = await ref
        .read(adminApiProvider)
        .setOwnerSwitch(line.key, on: on, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<OwnerSwitchDto>(:final value):
        _say(value.isOn ? 'شُغّل «${text.name}»' : 'أُوقف «${text.name}»');
        ref.invalidate(ownerSwitchesProvider);
      case Err<OwnerSwitchDto>(:final error):
        _say(ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<OwnerSwitchesDto> state = ref.watch(ownerSwitchesProvider);
    return state.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (Object e, _) => ListView(
        children: <Widget>[
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  ErrorPresenter.messageOf(e),
                  key: const Key('admin.switches.loadError'),
                  style: TextStyle(color: tokens.errorText),
                ),
                TextButton(
                  key: const Key('admin.switches.retry'),
                  onPressed: () => ref.invalidate(ownerSwitchesProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ],
      ),
      data: (OwnerSwitchesDto data) => ListView(
        key: const Key('admin.switches.list'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: <Widget>[
          const AdminSectionHeader(
            title: 'مفاتيح التشغيل',
            subtitle:
                'مفاتيح الطوارئ بيدك وبيد المالك الآخر وحدكما. لا يتغير مفتاح '
                'إلا بسبب، ويبقى من غيّره ومتى. يقرأ الخادم المفتاح في كل '
                'دورة، فلا يحتاج التغيير إعادة نشر.',
          ),
          for (final OwnerSwitchDto line in data.switches)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SwitchCard(
                line: line,
                busy: _busy,
                onChanged: (bool on) => unawaited(_turn(line, on)),
              ),
            ),
        ],
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.line,
    required this.busy,
    required this.onChanged,
  });

  final OwnerSwitchDto line;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final _SwitchText text = _textOf(line.key);
    final String? reason = line.reason;
    final String by = _byLabel(line.changedBy);
    final String changed = reason == null && line.changedBy == null
        ? 'لم يتغير منذ إنشائه'
        : <String>[
            'آخر تغيير: '
                '${formatTimestamp(context, line.changedAt.toIso8601String())}',
            if (by.isNotEmpty) by,
            if (reason != null) 'السبب: $reason',
          ].join(' · ');
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The card paints its own colour: the tile draws on a clear
          // Material of its own, or its ink would be hidden under it.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: Key('admin.switches.${line.key}'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                text.name,
                style: context.text.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                line.isOn ? text.whenOn : text.whenOff,
                key: Key('admin.switches.${line.key}.state'),
                style: context.text.bodySmall?.copyWith(
                  color: line.isOn ? tokens.textSecondary : tokens.errorText,
                  fontWeight: line.isOn ? FontWeight.w400 : FontWeight.w700,
                ),
              ),
              value: line.isOn,
              onChanged: busy ? null : onChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            changed,
            key: Key('admin.switches.${line.key}.changed'),
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks the owner why he turns a switch; null when he cancels.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.notice,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final String notice;
  final String confirmLabel;
  final bool destructive;

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
    final String reason = _reason.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.notice, key: const Key('admin.switches.dialog.notice')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('admin.switches.dialog.reason'),
              controller: _reason,
              maxLength: ownerSwitchReasonMaxLength,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'السبب',
                hintText: 'مثل: مراجعة نقاط الشهر قبل التتويج',
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
              key: const Key('admin.switches.dialog.ok'),
              label: widget.confirmLabel,
              variant: widget.destructive
                  ? AppButtonVariant.danger
                  : AppButtonVariant.primary,
              size: AppButtonSize.medium,
              onPressed: reason.isEmpty
                  ? null
                  : () => Navigator.of(context).pop<String>(reason),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('admin.switches.dialog.cancel'),
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
