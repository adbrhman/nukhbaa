/// قسم «الشعارات» في لوحة المشرف (السكربت 266، فوق مسارات 265 والهجرة
/// 0210، قرار المالك 2026-11-11): شعارات الأندية ملك لأصحابها، ويقرأ
/// التطبيق قائمتها من الخادم عند كل فتح.
///
/// يُخفي المالك شعاراً عند شكوى (بسبب، ومع اسم الشاكي إن وُجد)، فيختفي من
/// كل جهاز عند فتح التطبيق التالي، ثم يُظهره إن شاء؛ أو يحذفه نهائياً بعد
/// كتابة اسمه، فيُمحى ملفه؛ أو يوقف شعارات الأندية كلها بمفتاح واحد. وكل
/// تغيير يبقى في السجل بسببه. أعلام الدول ليست هنا: تبقى داخل التطبيق.
///
/// التبويب للمالك وحده (`ownerAdminEmail`)، والخادم يرفض غيره
/// (`admin.owner_only`).
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

/// `GET /admin/crests`.
final adminCrestsProvider = FutureProvider.autoDispose<AdminCrestsDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).adminCrests()) {
    Ok<AdminCrestsDto>(:final value) => value,
    Err<AdminCrestsDto>(:final error) => throw error,
  };
});

/// The longest reason or complainant the server keeps.
const int crestTextMaxLength = 200;

String _statusLabel(String status) => switch (status) {
  'active' => 'ظاهر',
  'hidden' => 'مخفي',
  'deleted' => 'محذوف',
  _ => status,
};

String _actionLabel(String action) => switch (action) {
  'hidden' => 'أُخفي',
  'shown' => 'أُظهر',
  'deleted' => 'حُذف',
  'clubs_on' => 'شُغّلت شعارات الأندية',
  'clubs_off' => 'أُوقفت شعارات الأندية',
  _ => action,
};

/// What the owner typed in a crest dialog.
typedef CrestAnswer = ({String reason, String? complainant});

/// The owner admin's crests tab.
class ClubCrestsSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const ClubCrestsSection({super.key});

  @override
  ConsumerState<ClubCrestsSection> createState() => _ClubCrestsSectionState();
}

class _ClubCrestsSectionState extends ConsumerState<ClubCrestsSection> {
  final TextEditingController _search = TextEditingController();
  String _filter = 'all';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _act(
    AdminCrestDto crest,
    String action, {
    required String done,
    String? reason,
    String? complainant,
    String? confirm,
  }) async {
    setState(() => _busy = true);
    final Result<String> result = await ref
        .read(adminApiProvider)
        .actOnCrest(
          crest.slug,
          action,
          reason: reason,
          complainant: complainant,
          confirm: confirm,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<String>():
        _say(done);
        ref.invalidate(adminCrestsProvider);
      case Err<String>(:final error):
        _say(ErrorPresenter.message(error));
    }
  }

  Future<void> _hide(AdminCrestDto crest) async {
    final CrestAnswer? answer = await showDialog<CrestAnswer>(
      context: context,
      builder: (_) => _CrestDialog(
        title: 'إخفاء «${crest.slug}»',
        notice:
            'يختفي الشعار من كل جهاز عند فتح التطبيق التالي، وتظهر مكانه دائرة '
            'بلون الفريق. ويمكنك إظهاره متى شئت.',
        confirmLabel: 'أخفِ الشعار',
        keyName: 'hide',
      ),
    );
    if (answer == null || !mounted) return;
    await _act(
      crest,
      'hide',
      done: 'أُخفي «${crest.slug}»',
      reason: answer.reason,
      complainant: answer.complainant,
    );
  }

  Future<void> _show(AdminCrestDto crest) => _act(
    crest,
    'show',
    done: 'أُظهر «${crest.slug}»',
    reason: 'أُعيد إظهاره',
  );

  Future<void> _delete(AdminCrestDto crest) async {
    final CrestAnswer? answer = await showDialog<CrestAnswer>(
      context: context,
      builder: (_) => _CrestDialog(
        title: 'حذف «${crest.slug}» نهائياً',
        notice:
            'يُمحى ملف الشعار ولا يعود. اكتب اسمه كما هو للتأكيد: ${crest.slug}',
        confirmLabel: 'احذف نهائياً',
        keyName: 'delete',
        confirmText: crest.slug,
        destructive: true,
      ),
    );
    if (answer == null || !mounted) return;
    await _act(
      crest,
      'delete',
      done: 'حُذف «${crest.slug}»',
      reason: answer.reason,
      complainant: answer.complainant,
      confirm: crest.slug,
    );
  }

  Future<void> _switch(bool enabled) async {
    final CrestAnswer? answer = await showDialog<CrestAnswer>(
      context: context,
      builder: (_) => _CrestDialog(
        title: enabled ? 'تشغيل شعارات الأندية' : 'إيقاف شعارات الأندية',
        notice: enabled
            ? 'تعود الشعارات الظاهرة إلى كل جهاز عند فتح التطبيق التالي.'
            : 'تختفي شعارات الأندية كلها من كل جهاز عند فتح التطبيق التالي، '
                  'وتظهر مكانها دوائر بألوان الفرق. أعلام الدول تبقى.',
        confirmLabel: enabled ? 'شغّل' : 'أوقف',
        keyName: 'switch',
        askComplainant: false,
      ),
    );
    if (answer == null || !mounted) return;
    setState(() => _busy = true);
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .setClubCrestsEnabled(enabled, reason: answer.reason);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<bool>():
        _say(enabled ? 'شُغّلت شعارات الأندية' : 'أُوقفت شعارات الأندية');
        ref.invalidate(adminCrestsProvider);
      case Err<bool>(:final error):
        _say(ErrorPresenter.message(error));
    }
  }

  List<AdminCrestDto> _shown(AdminCrestsDto data) {
    final String query = _search.text.trim().toLowerCase();
    return <AdminCrestDto>[
      for (final AdminCrestDto crest in data.crests)
        if ((_filter == 'all' || crest.status == _filter) &&
            (query.isEmpty || crest.slug.contains(query)))
          crest,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<AdminCrestsDto> state = ref.watch(adminCrestsProvider);
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
                  key: const Key('admin.crests.loadError'),
                  style: TextStyle(color: tokens.errorText),
                ),
                TextButton(
                  key: const Key('admin.crests.retry'),
                  onPressed: () => ref.invalidate(adminCrestsProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ],
      ),
      data: (AdminCrestsDto data) {
        final List<AdminCrestDto> shown = _shown(data);
        int count(String status) =>
            data.crests.where((AdminCrestDto c) => c.status == status).length;
        final List<Widget> top = <Widget>[
          const AdminSectionHeader(
            title: 'شعارات الأندية',
            subtitle:
                'الشعارات ملك لأصحابها، ويقرأ التطبيق قائمتها عند كل فتح. ما '
                'تخفيه أو تحذفه يختفي من كل جهاز عند فتح التطبيق التالي. '
                'أعلام الدول ليست هنا: تبقى داخل التطبيق. هذا القسم لك وحدك.',
          ),
          AdminCard(
            // The card paints its own colour: the tile draws on a clear
            // Material of its own, or its ink would be hidden under it.
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const Key('admin.crests.switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('شعارات الأندية ظاهرة'),
                subtitle: Text(
                  data.clubsEnabled
                      ? 'ظاهر ${count('active')} · مخفي ${count('hidden')} · '
                            'محذوف ${count('deleted')}'
                      : 'متوقفة: تظهر دوائر بألوان الفرق في كل مكان',
                ),
                value: data.clubsEnabled,
                onChanged: _busy ? null : (bool on) => unawaited(_switch(on)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AdminTextField(
            key: const Key('admin.crests.search'),
            controller: _search,
            hint: 'اسم الشعار بالإنجليزية، مثل arsenal',
            prefixIcon: Icons.search_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final (String id, String label) in <(String, String)>[
                ('all', 'الكل'),
                ('active', 'الظاهرة'),
                ('hidden', 'المخفية'),
                ('deleted', 'المحذوفة'),
              ])
                ChoiceChip(
                  key: Key('admin.crests.filter.$id'),
                  label: Text(label),
                  selected: _filter == id,
                  onSelected: (_) => setState(() => _filter = id),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('لا شعار هنا', key: Key('admin.crests.none')),
            ),
        ];
        final Widget log = _CrestLog(events: data.events);
        return ListView.builder(
          key: const Key('admin.crests.list'),
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          itemCount: top.length + shown.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (index < top.length) return top[index];
            final int row = index - top.length;
            if (row == shown.length) return log;
            final AdminCrestDto crest = shown[row];
            return _CrestRow(
              key: Key('admin.crests.row.${crest.slug}'),
              crest: crest,
              busy: _busy,
              onHide: () => unawaited(_hide(crest)),
              onShow: () => unawaited(_show(crest)),
              onDelete: () => unawaited(_delete(crest)),
            );
          },
        );
      },
    );
  }
}

class _CrestRow extends StatelessWidget {
  const _CrestRow({
    super.key,
    required this.crest,
    required this.busy,
    required this.onHide,
    required this.onShow,
    required this.onDelete,
  });

  final AdminCrestDto crest;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback onShow;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String? url = crest.url;
    final String? why = crest.reason;
    final String? who = crest.complainant;
    final Widget mark = SizedBox(
      width: 44,
      height: 44,
      child: url == null
          ? Icon(Icons.shield_outlined, color: tokens.textMuted)
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.shield_outlined, color: tokens.textMuted),
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Opacity(opacity: crest.status == 'active' ? 1 : 0.4, child: mark),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    crest.slug,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                    style: context.text.bodyLarge?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _statusLabel(crest.status),
                    key: Key('admin.crests.status.${crest.slug}'),
                    style: context.text.bodySmall?.copyWith(
                      color: crest.status == 'active'
                          ? tokens.textSecondary
                          : tokens.errorText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (crest.status != 'active' && why != null)
                    Text(
                      who == null
                          ? 'السبب: $why'
                          : 'السبب: $why · الشاكي: $who',
                      style: context.text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  if (crest.status != 'deleted') ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        if (crest.status == 'active')
                          AdminSecondaryButton(
                            key: Key('admin.crests.hide.${crest.slug}'),
                            label: 'إخفاء',
                            semanticsLabel: 'إخفاء: ${crest.slug}',
                            icon: Icons.visibility_off_rounded,
                            onPressed: busy ? null : onHide,
                          ),
                        if (crest.status == 'hidden')
                          AdminSecondaryButton(
                            key: Key('admin.crests.show.${crest.slug}'),
                            label: 'إظهار',
                            semanticsLabel: 'إظهار: ${crest.slug}',
                            icon: Icons.visibility_rounded,
                            onPressed: busy ? null : onShow,
                          ),
                        AdminSecondaryButton(
                          key: Key('admin.crests.delete.${crest.slug}'),
                          label: 'حذف',
                          semanticsLabel: 'حذف: ${crest.slug}',
                          icon: Icons.delete_forever_rounded,
                          onPressed: busy ? null : onDelete,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrestLog extends StatelessWidget {
  const _CrestLog({required this.events});

  final List<CrestEventDto> events;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: AdminCard(
        key: const Key('admin.crests.log'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'السجل',
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text('لا تغيير بعد'),
              ),
            for (final CrestEventDto event in events)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  <String>[
                    formatTimestamp(context, event.at),
                    if (event.slug != null)
                      '${_actionLabel(event.action)} «${event.slug}»'
                    else
                      _actionLabel(event.action),
                    'السبب: ${event.reason}',
                    if (event.complainant != null)
                      'الشاكي: ${event.complainant}',
                  ].join(' · '),
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks the owner why (and, for a complaint, who complained); for a delete,
/// asks him to type the crest's name too. Null when he cancels.
class _CrestDialog extends StatefulWidget {
  const _CrestDialog({
    required this.title,
    required this.notice,
    required this.confirmLabel,
    required this.keyName,
    this.confirmText,
    this.askComplainant = true,
    this.destructive = false,
  });

  final String title;
  final String notice;
  final String confirmLabel;

  /// Keys the dialog's fields: `admin.crests.<keyName>.reason`, ...
  final String keyName;

  /// What must be typed to confirm, or null when nothing is.
  final String? confirmText;
  final bool askComplainant;
  final bool destructive;

  @override
  State<_CrestDialog> createState() => _CrestDialogState();
}

class _CrestDialogState extends State<_CrestDialog> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _complainant = TextEditingController();
  final TextEditingController _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    _complainant.dispose();
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String reason = _reason.text.trim();
    final String? mustType = widget.confirmText;
    final bool ready =
        reason.isNotEmpty &&
        (mustType == null || _typed.text.trim() == mustType);
    final String key = 'admin.crests.${widget.keyName}';
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.notice),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: Key('$key.reason'),
              controller: _reason,
              maxLength: crestTextMaxLength,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'السبب',
                hintText: 'مثل: طلب النادي إزالته',
              ),
            ),
            if (widget.askComplainant)
              TextField(
                key: Key('$key.complainant'),
                controller: _complainant,
                maxLength: crestTextMaxLength,
                decoration: const InputDecoration(
                  labelText: 'الشاكي (اختياري)',
                  hintText: 'الجهة أو البريد',
                ),
              ),
            if (mustType != null)
              TextField(
                key: Key('$key.confirm'),
                controller: _typed,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                decoration: InputDecoration(labelText: 'اكتب: $mustType'),
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
              key: Key('$key.ok'),
              label: widget.confirmLabel,
              variant: widget.destructive
                  ? AppButtonVariant.danger
                  : AppButtonVariant.primary,
              size: AppButtonSize.medium,
              // Read when pressed: the complainant field redraws nothing
              // as it is typed.
              onPressed: ready
                  ? () {
                      final String complainant = _complainant.text.trim();
                      Navigator.of(context).pop<CrestAnswer>((
                        reason: _reason.text.trim(),
                        complainant: complainant.isEmpty ? null : complainant,
                      ));
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: Key('$key.cancel'),
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
