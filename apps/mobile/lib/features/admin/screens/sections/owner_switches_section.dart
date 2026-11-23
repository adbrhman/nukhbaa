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
import '../../widgets/app_release_card.dart';

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
        'يعود التتويج التلقائي خلال دقيقتين، فيُتوَّج كل شهر انتهت مبارياته '
        'قبل 3 أيام أو أقل، ويستطيع المشرفون التتويج. الشهر الأقدم تتوّجه '
        'يدوياً. تأكد من صحة النقاط قبل التشغيل.',
    turnOff:
        'يتوقف التتويج التلقائي خلال دقيقتين، ويُرفض تتويج المشرفين. يصلك '
        'تنبيه مرة لكل شهر ينتظر، وتستطيع أنت التتويج يدوياً. لا يُلغى '
        'تتويج تم.',
  ),
  // NK291_06
  'predictions' => (
    name: 'حفظ التوقعات',
    whenOn: 'يعمل: يحفظ اللاعبون توقعاتهم ويعدّلونها حتى بداية المباراة.',
    whenOff:
        'موقوف: لا يُحفظ توقع جديد ولا يُعدَّل توقع، للجميع. التصفح والنتائج '
        'تعمل، والتوقعات المحفوظة باقية.',
    turnOn: 'يعود حفظ التوقعات فوراً من الطلب التالي.',
    turnOff:
        'يُرفض كل توقع جديد أو تعديل فوراً، ويقرأ اللاعب أن الحفظ متوقف '
        'مؤقتاً. لا يُحذف أي توقع محفوظ، والمباريات التي تبدأ أثناء الإيقاف '
        'تُقفل كالمعتاد.',
  ),
  'chat' => (
    name: 'دردشة المواجهات',
    whenOn: 'تعمل: يكتب اللاعبون في دردشة مجموعتهم.',
    whenOff: 'موقوفة: لا تُرسل رسالة جديدة، والرسائل السابقة تُقرأ.',
    turnOn: 'تعود الدردشة فوراً من الطلب التالي.',
    turnOff:
        'تُرفض كل رسالة جديدة فوراً، ويقرأ اللاعب أن الدردشة متوقفة مؤقتاً. '
        'الرسائل السابقة تبقى.',
  ),
  // NK304_01
  'h2h_rounds' => (
    name: 'اعتماد جولات المواجهات',
    whenOn: 'يعمل: تُعتمد الجولات الجديدة تلقائياً ويعتمدها المشرفون.',
    whenOff:
        'موقوف: لا تُعتمد جولة جديدة، لا تلقائياً ولا من المشرفين. الجولات '
        'المعتمدة تُقفل وتُحسم كالمعتاد.',
    turnOn: 'يعود اعتماد الجولات من الدورة التالية، فوراً للمشرفين.',
    turnOff:
        'يتوقف اعتماد الجولات الجديدة خلال دقيقتين، ويُرفض اعتماد المشرفين '
        'فوراً. الجولات المعتمدة تُقفل وتُحسم كالمعتاد.',
  ),
  'h2h_cup' => (
    name: 'كأس المواجهات',
    whenOn: 'يعمل: يُدار الكأس تلقائياً بعد انتهاء جولات الشهر.',
    whenOff:
        'موقوف: لا يُسجَّل متأهل ولا مرحلة ولا نتيجة ولا لقب، وما سُجّل '
        'باقٍ. جولات الشهر التالي تنتظر انتهاء الكأس.',
    turnOn: 'يعود الكأس إلى العمل من الدورة التالية، ويكمل من حيث توقف.',
    turnOff:
        'يتوقف الكأس خلال دقيقتين: لا قرعة ولا نتيجة ولا لقب. لا يُحذف شيء '
        'مما سُجّل، وجولات الشهر التالي تنتظر انتهاءه.',
  ),
  'h2h_cup_crowning' => (
    name: 'تتويج كأس المواجهات',
    whenOn: 'يعمل: يُتوَّج كل مسار بعد نهائيه.',
    whenOff:
        'موقوف: يستمر الكأس ولا يُتوَّج أي مسار. جولات الشهر التالي تنتظر '
        'التتويج.',
    turnOn: 'يعود التتويج من الدورة التالية، فتُتوَّج المسارات المنتظرة.',
    turnOff:
        'يتوقف التتويج خلال دقيقتين، ويستمر الكأس حتى النهائي. لا يُلغى '
        'لقب تم، وجولات الشهر التالي تنتظر.',
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
          // script 292: the app's mode, above the switches.
          const _AppModeCard(),
          for (final OwnerSwitchDto line in data.switches)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SwitchCard(
                line: line,
                busy: _busy,
                onChanged: (bool on) => unawaited(_turn(line, on)),
              ),
            ),
          // NK293_01
          // script 293: the build floor of each channel (APK and Play),
          // within reach in an emergency: clearing it lets the blocked
          // players in again, with no release.
          const SizedBox(height: AppSpacing.md),
          const AppReleaseCard(),
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

// NK292_10
/// `GET /owner/mode` (script 292).
final ownerAppModeProvider = FutureProvider.autoDispose<AppModeDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).ownerAppMode()) {
    Ok<AppModeDto>(:final value) => value,
    Err<AppModeDto>(:final error) => throw error,
  };
});

/// Each mode: its name, what the players get, and what setting it does.
const List<(String, String, String, String)> _modes = [
  (
    AppModeDto.normal,
    'عادي',
    'كل شيء يعمل.',
    'يعود كل شيء للعمل خلال 10 ثوانٍ.',
  ),
  (
    AppModeDto.readOnly,
    'قراءة فقط',
    'يتصفح اللاعبون النتائج والترتيب. حفظ التوقعات والدردشة والمجموعات '
        'والاسم والصورة متوقفة. الدخول والدعم وحذف الحساب تعمل.',
    'خلال 10 ثوانٍ يقرأ كل لاعب يحاول الحفظ أن نُخبة في وضع الصيانة. '
        'المشرفون مستثنون ليختبروا، والمهام المجدولة تستمر (أوقفها '
        'بمفاتيحها).',
  ),
  (
    AppModeDto.closed,
    'مغلق',
    'لا يعمل للاعبين إلا الدخول وحذف الحساب.',
    'خلال 10 ثوانٍ يقرأ كل لاعب أن نُخبة متوقفة مؤقتاً للصيانة. المشرفون '
        'مستثنون، والمهام المجدولة تستمر (أوقفها بمفاتيحها).',
  ),
];

(String, String, String, String) _modeOf(String wire) => _modes.firstWhere(
  ((String, String, String, String) m) => m.$1 == wire,
  orElse: () => (wire, wire, '', ''),
);

/// «وضع التطبيق»: normal, read only or closed, always for a reason
/// (script 292).
class _AppModeCard extends ConsumerStatefulWidget {
  const _AppModeCard();

  @override
  ConsumerState<_AppModeCard> createState() => _AppModeCardState();
}

class _AppModeCardState extends ConsumerState<_AppModeCard> {
  bool _busy = false;

  Future<void> _set(String wire) async {
    final (String, String, String, String) mode = _modeOf(wire);
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'وضع التطبيق: ${mode.$2}',
        notice: mode.$4,
        confirmLabel: 'غيّر الوضع',
        destructive: wire != AppModeDto.normal,
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final Result<AppModeDto> result = await ref
        .read(adminApiProvider)
        .setOwnerAppMode(wire, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    final String text = switch (result) {
      Ok<AppModeDto>() => 'صار وضع التطبيق: ${mode.$2}',
      Err<AppModeDto>(:final error) => ErrorPresenter.message(error),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    ref.invalidate(ownerAppModeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<AppModeDto> state = ref.watch(ownerAppModeProvider);
    final Widget body = state.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: LinearProgressIndicator(),
      ),
      error: (Object e, _) => Text(
        ErrorPresenter.messageOf(e),
        key: const Key('admin.mode.loadError'),
        style: TextStyle(color: tokens.errorText),
      ),
      data: (AppModeDto data) {
        final (String, String, String, String) now = _modeOf(data.mode);
        final String? reason = data.reason;
        final String by = _byLabel(data.changedBy);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              now.$3,
              key: const Key('admin.mode.state'),
              style: context.text.bodySmall?.copyWith(
                color: data.mode == AppModeDto.normal
                    ? tokens.textSecondary
                    : tokens.errorText,
                fontWeight: data.mode == AppModeDto.normal
                    ? FontWeight.w400
                    : FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final (String, String, String, String) m in _modes)
                  ChoiceChip(
                    key: Key('admin.mode.${m.$1}'),
                    label: Text(m.$2),
                    selected: data.mode == m.$1,
                    onSelected: _busy || data.mode == m.$1
                        ? null
                        : (_) => unawaited(_set(m.$1)),
                  ),
              ],
            ),
            if (reason != null || data.changedBy != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                <String>[
                  'آخر تغيير: '
                      '${formatTimestamp(context, data.changedAt.toIso8601String())}',
                  if (by.isNotEmpty) by,
                  if (reason != null) 'السبب: $reason',
                ].join(' · '),
                key: const Key('admin.mode.changed'),
                style: context.text.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ],
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AdminCard(
        key: const Key('admin.mode.card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'وضع التطبيق',
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            body,
          ],
        ),
      ),
    );
  }
}
