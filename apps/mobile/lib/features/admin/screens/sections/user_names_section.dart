/// قسم «أسماء المستخدمين» في لوحة المشرف: الأسماء المكررة، وتعديل اسم أي
/// لاعب، وإخفاء الحساب من كل اللوحات أو إعادته.
///
/// الأسماء مميّزة منذ migration 0084: لا يأخذ لاعبان الاسم نفسه (تُتجاهل
/// المسافات وحالة الأحرف والتشكيل، وأ/إ/آ = ا، ة = ه، ى = ي). الأسماء
/// المكررة من قبل تبقى حتى يعدّل المشرف أحدها من هنا.
///
/// «الإخفاء من اللوحات» هو تعليق الحساب: يختفي هو ونقاطه من كل اللوحات، ولا
/// يُحذف شيء؛ إعادة التفعيل تعيده بنقاطه كما كانت. الخادم وحده يقرر.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// `GET /admin/duplicate-names`.
final adminDuplicateNamesProvider =
    FutureProvider.autoDispose<DuplicateNamesDto>((ref) async {
      return switch (await ref.watch(adminApiProvider).duplicateNames()) {
        Ok<DuplicateNamesDto>(:final value) => value,
        Err<DuplicateNamesDto>(:final error) => throw error,
      };
    });

/// The "user names" section of the admin hub.
class UserNamesSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const UserNamesSection({super.key});

  @override
  ConsumerState<UserNamesSection> createState() => _UserNamesSectionState();
}

class _UserNamesSectionState extends ConsumerState<UserNamesSection> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  List<UserSummaryDto>? _found;
  UserSummaryDto? _selected;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _select(UserSummaryDto user) {
    setState(() {
      _selected = user;
      _name.text = user.displayName;
      _error = null;
    });
  }

  Future<void> _runSearch() async {
    final String term = _search.text.trim();
    if (term.isEmpty) return;
    setState(() => _busy = true);
    final Result<UserListDto> result = await ref
        .read(adminApiProvider)
        .listUsers(search: term);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok<UserListDto>(:final value):
          _found = value.users;
          _error = null;
        case Err<UserListDto>(:final error):
          _found = null;
          _error = ErrorPresenter.message(error);
      }
    });
  }

  /// The reason, or `null` after telling the admin it is missing.
  String? _reasonOrComplain() {
    final String reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'اكتب السبب أولاً');
      return null;
    }
    return reason;
  }

  Future<void> _rename() async {
    final UserSummaryDto? user = _selected;
    final String name = _name.text.trim();
    if (user == null) return;
    if (name.isEmpty) {
      setState(() => _error = 'اكتب الاسم الجديد');
      return;
    }
    final String? reason = _reasonOrComplain();
    if (reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<UserSummaryDto> result = await ref
        .read(adminApiProvider)
        .renameUser(user.id, displayName: name, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<UserSummaryDto>(:final value):
        _select(value);
        _snack('تم تعديل الاسم إلى «${value.displayName}»');
        ref.invalidate(adminDuplicateNamesProvider);
      case Err<UserSummaryDto>(:final error):
        setState(() => _error = ErrorPresenter.message(error));
    }
  }

  Future<void> _setHidden({required bool hidden}) async {
    final UserSummaryDto? user = _selected;
    if (user == null) return;
    final String? reason = _reasonOrComplain();
    if (reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(adminApiProvider);
    final Result<UserSanctionResultDto> result = hidden
        ? await api.suspendUser(user.id, reason)
        : await api.reinstateUser(user.id, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<UserSanctionResultDto>(:final value):
        _select(
          UserSummaryDto(
            id: user.id,
            email: user.email,
            displayName: user.displayName,
            status: value.status,
          ),
        );
        _snack(
          value.status == 'suspended'
              ? 'أُخفي الحساب ونقاطه من كل اللوحات'
              : 'عاد الحساب ونقاطه إلى اللوحات',
        );
        ref.invalidate(adminDuplicateNamesProvider);
      case Err<UserSanctionResultDto>(:final error):
        setState(() => _error = ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final UserSummaryDto? selected = _selected;
    final List<UserSummaryDto>? found = _found;
    final String? error = _error;
    return ListView(
      key: const Key('admin.names.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'أسماء المستخدمين',
          subtitle:
              'لا يأخذ لاعبان الاسم نفسه. عدّل الاسم المكرر، أو أخفِ الحساب '
              'ونقاطه من كل اللوحات دون حذف شيء.',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AdminTextField(
                key: const Key('admin.names.searchField'),
                controller: _search,
                hint: 'ابحث بالاسم أو البريد',
                prefixIcon: Icons.search_rounded,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminSecondaryButton(
                key: const Key('admin.names.searchButton'),
                label: 'بحث',
                icon: Icons.search_rounded,
                onPressed: _busy ? null : () => unawaited(_runSearch()),
              ),
              if (found != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                if (found.isEmpty)
                  const Text('لا يوجد مستخدمون مطابقون.')
                else
                  for (final UserSummaryDto user in found)
                    _UserTile(
                      key: Key('admin.names.found.${user.id}'),
                      user: user,
                      selected: user.id == selected?.id,
                      onTap: () => _select(user),
                    ),
              ],
            ],
          ),
        ),
        if (selected != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          AdminCard(
            key: const Key('admin.names.editor'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  selected.email ?? selected.id,
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  selected.status == 'suspended'
                      ? 'مخفي من اللوحات'
                      : 'ظاهر في اللوحات',
                  key: const Key('admin.names.status'),
                  style: TextStyle(
                    color: selected.status == 'suspended'
                        ? tokens.error
                        : tokens.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AdminTextField(
                  key: const Key('admin.names.nameField'),
                  controller: _name,
                  hint: 'الاسم الجديد',
                  prefixIcon: Icons.badge_rounded,
                  enabled: !_busy,
                ),
                const SizedBox(height: AppSpacing.sm),
                AdminTextField(
                  key: const Key('admin.names.reasonField'),
                  controller: _reason,
                  hint: 'السبب (إلزامي)',
                  prefixIcon: Icons.notes_rounded,
                  enabled: !_busy,
                ),
                if (error != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    error,
                    key: const Key('admin.names.error'),
                    style: TextStyle(color: tokens.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AdminPrimaryButton(
                  key: const Key('admin.names.save'),
                  label: 'حفظ الاسم',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : () => unawaited(_rename()),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'الإخفاء يرفع الحساب ونقاطه من كل اللوحات دون حذف شيء.',
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (selected.status == 'suspended')
                  AdminSecondaryButton(
                    key: const Key('admin.names.show'),
                    label: 'إعادة إلى اللوحات',
                    icon: Icons.visibility_rounded,
                    onPressed: _busy
                        ? null
                        : () => unawaited(_setHidden(hidden: false)),
                  )
                else
                  AdminSecondaryButton(
                    key: const Key('admin.names.hide'),
                    label: 'إخفاء من اللوحات',
                    icon: Icons.visibility_off_rounded,
                    onPressed: _busy
                        ? null
                        : () => unawaited(_setHidden(hidden: true)),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _DuplicatesCard(selectedId: selected?.id, onSelect: _select),
      ],
    );
  }
}

class _DuplicatesCard extends ConsumerWidget {
  const _DuplicatesCard({required this.selectedId, required this.onSelect});

  final String? selectedId;
  final ValueChanged<UserSummaryDto> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<DuplicateNamesDto> duplicates = ref.watch(
      adminDuplicateNamesProvider,
    );
    return AdminCard(
      key: const Key('admin.names.duplicates'),
      child: duplicates.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (Object error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              error is AppError
                  ? ErrorPresenter.message(error)
                  : 'تعذّر تحميل الأسماء المكررة',
              style: TextStyle(color: tokens.error),
            ),
            TextButton(
              onPressed: () => ref.invalidate(adminDuplicateNamesProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
        data: (DuplicateNamesDto data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              data.groups.isEmpty
                  ? 'لا توجد أسماء مكررة'
                  : 'أسماء مكررة: ${data.groups.length}',
              key: const Key('admin.names.duplicatesTitle'),
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (data.groups.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'اضغط على حساب لتعديل اسمه. يكفي أن يبقى الاسم لحساب واحد.',
                style: context.text.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
            for (final List<UserSummaryDto> group in data.groups) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              for (final UserSummaryDto user in group)
                _UserTile(
                  key: Key('admin.names.duplicate.${user.id}'),
                  user: user,
                  selected: user.id == selectedId,
                  onTap: () => onSelect(user),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    super.key,
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final UserSummaryDto user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final bool hidden = user.status == 'suspended';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      // A ListTile paints its ink on the nearest Material; the card's own
      // background would hide it, so the tile gets a Material of its own.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: onTap,
          selected: selected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: tokens.border),
          ),
          title: Text(user.displayName.isEmpty ? user.id : user.displayName),
          subtitle: Text(
            hidden
                ? '${user.email ?? user.id} · مخفي من اللوحات'
                : user.email ?? user.id,
          ),
          trailing: const Icon(Icons.edit_rounded),
        ),
      ),
    );
  }
}
