/// تبويب «المشرفون» في «الإدارة العامة للمالك» (السكربت 294، البند 4 من
/// تقرير المالك، فوق الهجرة 0223): يرقّي المالك لاعباً إلى مشرف، أو يسحب
/// إشراف مشرف فتنتهي جلساته معه، أو ينهي جلسات حساب، وكل ذلك بسبب مكتوب
/// يبقى في السجل.
///
/// لا يُسحب إشراف صاحب مقعد مالك من هنا، فلا يُعطَّل آخر مالك أبداً.
/// والمشرف المسحوب يعود لاعباً من طلبه التالي، لأن الخادم يقرأ الدور في كل
/// طلب. والخادم يجيب غير المالكَين بمسار غير موجود.
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

// NK294_09
/// `GET /owner/admins`.
final ownerAdminsProvider = FutureProvider.autoDispose<OwnerAdminsDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).ownerAdmins()) {
    Ok<OwnerAdminsDto>(:final value) => value,
    Err<OwnerAdminsDto>(:final error) => throw error,
  };
});

String _actionLabel(String action) => switch (action) {
  'promote' => 'رُقّي إلى مشرف',
  'revoke' => 'سُحب إشرافه',
  'end_sessions' => 'أُنهيت جلساته',
  _ => action,
};

/// What each action says before it runs: its title, what it does, and its
/// button.
(String, String, String) _askFor(String action, String name) =>
    switch (action) {
      'promote' => (
        'ترقية «$name» إلى مشرف',
        'يصير مشرفاً من طلبه التالي، ويرى لوحة إدارة نُخبة دون صفحة المالك.',
        'رقّه',
      ),
      'revoke' => (
        'سحب إشراف «$name»',
        'يعود لاعباً من طلبه التالي، وتنتهي جلساته على كل أجهزته فيسجّل '
            'الدخول من جديد. نقاطه وتوقعاته تبقى.',
        'اسحب الإشراف',
      ),
      _ => (
        'إنهاء جلسات «$name»',
        'يخرج من كل أجهزته ويسجّل الدخول من جديد. ما معه من دخول حالي يبقى '
            'ساعة على الأكثر. دوره لا يتغير.',
        'أنهِ الجلسات',
      ),
    };

/// The owners' tab of admins.
class OwnerAdminsSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const OwnerAdminsSection({super.key});

  @override
  ConsumerState<OwnerAdminsSection> createState() => _OwnerAdminsSectionState();
}

class _OwnerAdminsSectionState extends ConsumerState<OwnerAdminsSection> {
  final TextEditingController _search = TextEditingController();
  List<UserSummaryDto>? _found;
  bool _searching = false;
  String? _busyId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _find() async {
    final String query = _search.text.trim();
    if (query.isEmpty) {
      _say('اكتب اسماً أو بريداً أولاً');
      return;
    }
    setState(() => _searching = true);
    final Result<UserListDto> result = await ref
        .read(adminApiProvider)
        .listUsers(search: query, limit: 20);
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (result case Ok<UserListDto>(:final value)) _found = value.users;
    });
    if (result case Err<UserListDto>(:final error)) {
      _say(ErrorPresenter.message(error));
    }
  }

  Future<void> _act(String userId, String name, String action) async {
    final (String title, String notice, String confirm) = _askFor(action, name);
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: title,
        notice: notice,
        confirmLabel: confirm,
        destructive: action != 'promote',
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busyId = userId);
    final Result<int> result = await ref
        .read(adminApiProvider)
        .actOnAdmin(userId, action, reason: reason);
    if (!mounted) return;
    setState(() => _busyId = null);
    switch (result) {
      case Ok<int>(:final value):
        _say(
          action == 'promote'
              ? '«$name» صار مشرفاً'
              : '«$name»: ${_actionLabel(action)} (جلسات منتهية: $value)',
        );
        ref.invalidate(ownerAdminsProvider);
      case Err<int>(:final error):
        _say(ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<OwnerAdminsDto> state = ref.watch(ownerAdminsProvider);
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
                  key: const Key('admin.admins.loadError'),
                  style: TextStyle(color: tokens.errorText),
                ),
                TextButton(
                  key: const Key('admin.admins.retry'),
                  onPressed: () => ref.invalidate(ownerAdminsProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ],
      ),
      data: (OwnerAdminsDto data) {
        final Set<String> adminIds = <String>{
          for (final OwnerAdminDto a in data.admins) a.id,
        };
        final List<UserSummaryDto> found = _found ?? const <UserSummaryDto>[];
        return ListView(
          key: const Key('admin.admins.list'),
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: <Widget>[
            const AdminSectionHeader(
              title: 'المشرفون',
              subtitle:
                  'رقِّ لاعباً، أو اسحب إشراف مشرف فتنتهي جلساته معه، أو أنهِ '
                  'جلسات حساب. كل تغيير يحتاج سبباً ويبقى في السجل. إشراف '
                  'المالكَين لا يُسحب من هنا.',
            ),
            for (final OwnerAdminDto admin in data.admins)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AdminCard(
                  key: Key('admin.admins.row.${admin.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        admin.displayName.isEmpty ? '—' : admin.displayName,
                        style: context.text.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        <String>[
                          if (admin.isOwner) 'مالك',
                          if (!admin.active) 'موقوف',
                          if (admin.email != null) admin.email!,
                        ].join(' · '),
                        key: Key('admin.admins.about.${admin.id}'),
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                      if (!admin.isOwner) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: <Widget>[
                            AdminSecondaryButton(
                              key: Key('admin.admins.revoke.${admin.id}'),
                              label: 'اسحب الإشراف',
                              semanticsLabel:
                                  'اسحب الإشراف: ${admin.displayName}',
                              icon: Icons.person_remove_rounded,
                              onPressed: _busyId != null
                                  ? null
                                  : () => unawaited(
                                      _act(
                                        admin.id,
                                        admin.displayName,
                                        'revoke',
                                      ),
                                    ),
                            ),
                            AdminSecondaryButton(
                              key: Key('admin.admins.end.${admin.id}'),
                              label: 'أنهِ الجلسات',
                              semanticsLabel:
                                  'أنهِ الجلسات: ${admin.displayName}',
                              icon: Icons.logout_rounded,
                              onPressed: _busyId != null
                                  ? null
                                  : () => unawaited(
                                      _act(
                                        admin.id,
                                        admin.displayName,
                                        'end_sessions',
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'ترقية لاعب إلى مشرف',
                    style: context.text.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AdminTextField(
                    key: const Key('admin.admins.searchField'),
                    controller: _search,
                    hint: 'الاسم أو البريد',
                    prefixIcon: Icons.search_rounded,
                    enabled: !_searching,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AdminSecondaryButton(
                    key: const Key('admin.admins.search'),
                    label: 'بحث',
                    icon: Icons.search_rounded,
                    loading: _searching,
                    onPressed: _searching ? null : () => unawaited(_find()),
                  ),
                  for (final UserSummaryDto user in found)
                    if (!adminIds.contains(user.id))
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                user.displayName.isEmpty
                                    ? (user.email ?? user.id)
                                    : user.displayName,
                              ),
                            ),
                            AdminSecondaryButton(
                              key: Key('admin.admins.promote.${user.id}'),
                              label: 'رقِّ',
                              semanticsLabel: 'رقِّ: ${user.displayName}',
                              icon: Icons.person_add_rounded,
                              onPressed: _busyId != null
                                  ? null
                                  : () => unawaited(
                                      _act(
                                        user.id,
                                        user.displayName,
                                        'promote',
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AdminCard(
              key: const Key('admin.admins.log'),
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
                  if (data.changes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.sm),
                      child: Text('لا تغيير بعد'),
                    ),
                  for (final RoleChangeDto change in data.changes)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        <String>[
                          formatTimestamp(context, change.at.toIso8601String()),
                          '«${change.userName}» ${_actionLabel(change.action)}',
                          'السبب: ${change.reason}',
                          if (change.byName != null) 'بواسطة ${change.byName}',
                        ].join(' · '),
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Asks the owner why; null when he cancels.
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
            Text(widget.notice),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('admin.admins.dialog.reason'),
              controller: _reason,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'السبب'),
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
              key: const Key('admin.admins.dialog.ok'),
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
              key: const Key('admin.admins.dialog.cancel'),
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
