/// قسم «الأشخاص» في لوحة المشرف (السكربت 264، فوق مسارات 263 والهجرة
/// 0209، قرار المالك 2026-11-12): شخص واحد خلف عدة حسابات.
///
/// للشخص حسابان على الأكثر يُحتسبان: الأساسي، وثانٍ إن أراد المالك. وما
/// زاد يُخفى من كل ترتيب وقرعة وتتويج، ويبقى صاحبه يدخل ويتوقع. تعديل
/// الربط أو فكّه يعيد ما أخفاه الربط وحده.
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
import '../../../../core/providers.dart';
import '../../../../core/ui/app_dialog.dart';
import '../../widgets/admin_ui_kit.dart';

/// `GET /admin/person-links`.
final adminPersonLinksProvider = FutureProvider.autoDispose<PersonLinksDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).personLinks()) {
    Ok<PersonLinksDto>(:final value) => value,
    Err<PersonLinksDto>(:final error) => throw error,
  };
});

/// What an account is in the person being set.
enum PersonRole {
  /// Counts; the person's main account.
  main,

  /// Counts too.
  second,

  /// Hidden from every board.
  hidden,
}

String _name(UserSummaryDto user) =>
    user.displayName.isEmpty ? (user.email ?? user.id) : user.displayName;

String _roleLabel(PersonRole role) => switch (role) {
  PersonRole.main => 'أساسي',
  PersonRole.second => 'ثانٍ',
  PersonRole.hidden => 'يُخفى',
};

/// The owner admin's "people" tab.
class PersonLinksSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const PersonLinksSection({super.key});

  @override
  ConsumerState<PersonLinksSection> createState() => _PersonLinksSectionState();
}

class _PersonLinksSectionState extends ConsumerState<PersonLinksSection> {
  final TextEditingController _search = TextEditingController();
  List<UserSummaryDto>? _found;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  /// The person being set: each chosen account and its role, in order.
  final Map<String, (UserSummaryDto, PersonRole)> _draft =
      <String, (UserSummaryDto, PersonRole)>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final String query = _search.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'اكتب اسماً أو بريداً أولاً');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    final Result<UserListDto> result = await ref
        .read(adminApiProvider)
        .listUsers(search: query, limit: 20);
    if (!mounted) return;
    setState(() {
      _searching = false;
      switch (result) {
        case Ok<UserListDto>(:final value):
          _found = value.users;
        case Err<UserListDto>(:final error):
          _error = ErrorPresenter.message(error);
      }
    });
  }

  /// Puts [user] in the person as [role]; a second main or second account
  /// moves the one before it to the hidden ones.
  void _choose(UserSummaryDto user, PersonRole role) {
    setState(() {
      _error = null;
      if (role != PersonRole.hidden) {
        for (final MapEntry<String, (UserSummaryDto, PersonRole)> e
            in _draft.entries.toList()) {
          if (e.key != user.id && e.value.$2 == role) {
            _draft[e.key] = (e.value.$1, PersonRole.hidden);
          }
        }
      }
      _draft[user.id] = (user, role);
    });
  }

  void _drop(String id) => setState(() => _draft.remove(id));

  /// Loads [person] into the form, to change it.
  void _edit(LinkedPersonDto person) {
    setState(() {
      _error = null;
      _draft.clear();
      for (final LinkedAccountDto account in person.accounts) {
        _draft[account.user.id] = (
          account.user,
          account.user.id == person.mainId
              ? PersonRole.main
              : (account.counted ? PersonRole.second : PersonRole.hidden),
        );
      }
    });
  }

  String? _mainId() {
    for (final MapEntry<String, (UserSummaryDto, PersonRole)> e
        in _draft.entries) {
      if (e.value.$2 == PersonRole.main) return e.key;
    }
    return null;
  }

  Future<void> _save() async {
    final String? main = _mainId();
    if (main == null) {
      setState(() => _error = 'اختر الحساب الأساسي');
      return;
    }
    if (_draft.length < 2) {
      setState(() => _error = 'اختر حسابين على الأقل للشخص الواحد');
      return;
    }
    String? second;
    final List<String> others = <String>[];
    for (final MapEntry<String, (UserSummaryDto, PersonRole)> e
        in _draft.entries) {
      switch (e.value.$2) {
        case PersonRole.main:
          break;
        case PersonRole.second:
          second = e.key;
        case PersonRole.hidden:
          others.add(e.key);
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .setPerson(main, secondId: second, otherIds: others);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Ok<bool>():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              others.isEmpty
                  ? 'رُبطت الحسابات كشخص واحد'
                  : 'رُبطت الحسابات، وأُخفي ${others.length} من كل اللوحات',
            ),
          ),
        );
        setState(() {
          _draft.clear();
          _found = null;
          _search.clear();
        });
        ref.invalidate(adminPersonLinksProvider);
      case Err<bool>(:final error):
        setState(() => _error = ErrorPresenter.message(error));
    }
  }

  Future<void> _unlink(LinkedPersonDto person) async {
    final String name = _name(person.accounts.first.user);
    final bool? sure = await AppDialog.confirm(
      context,
      title: 'فك ربط «$name»؟',
      message:
          'تعود ظاهرة الحسابات التي أخفاها الربط بنقاطها كما هي. ويبقى مخفياً '
          'ما أخفيته أنت من «المخفيون».',
      confirmLabel: 'فك الربط',
      cancelLabel: 'إلغاء',
    );
    if (sure != true || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Result<int> result = await ref
        .read(adminApiProvider)
        .unlinkPerson(person.mainId);
    if (!mounted) return;
    switch (result) {
      case Ok<int>():
        messenger.showSnackBar(SnackBar(content: Text('فُك ربط «$name»')));
        ref.invalidate(adminPersonLinksProvider);
      case Err<int>(:final error):
        messenger.showSnackBar(
          SnackBar(content: Text(ErrorPresenter.message(error))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<PersonLinksDto> people = ref.watch(
      adminPersonLinksProvider,
    );
    final String? error = _error;
    final List<UserSummaryDto>? found = _found;
    return ListView(
      key: const Key('admin.people.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'شخص واحد خلف عدة حسابات',
          subtitle:
              'للشخص حسابان على الأكثر يُحتسبان: الأساسي، وثانٍ إن شئت. وما '
              'زاد يُخفى من كل ترتيب وقرعة وتتويج، ويبقى صاحبه يدخل ويتوقع. '
              'هذا القسم لك وحدك.',
        ),
        AdminCard(
          key: const Key('admin.people.form'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'ربط حسابات شخص',
                style: context.text.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminTextField(
                key: const Key('admin.people.searchField'),
                controller: _search,
                hint: 'الاسم أو البريد',
                prefixIcon: Icons.search_rounded,
                enabled: !_searching,
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminSecondaryButton(
                key: const Key('admin.people.search'),
                label: 'بحث',
                icon: Icons.search_rounded,
                loading: _searching,
                onPressed: _searching ? null : () => unawaited(_find()),
              ),
              if (found != null && found.isEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'لا يوجد لاعب بهذا الاسم أو البريد',
                  key: Key('admin.people.none'),
                ),
              ],
              for (final UserSummaryDto user
                  in found ?? const <UserSummaryDto>[])
                _AccountRow(
                  key: Key('admin.people.found.${user.id}'),
                  user: user,
                  role: _draft[user.id]?.$2,
                  onChoose: (PersonRole role) => _choose(user, role),
                ),
              if (_draft.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'الشخص',
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final (UserSummaryDto user, PersonRole role)
                    in _draft.values)
                  _AccountRow(
                    key: Key('admin.people.draft.${user.id}'),
                    roleKey: 'draftRole',
                    user: user,
                    role: role,
                    onChoose: (PersonRole next) => _choose(user, next),
                    onDrop: () => _drop(user.id),
                  ),
              ],
              if (error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  error,
                  key: const Key('admin.people.error'),
                  style: TextStyle(color: tokens.errorText),
                ),
              ],
              if (_draft.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                AdminPrimaryButton(
                  key: const Key('admin.people.save'),
                  label: 'حفظ الربط',
                  icon: Icons.link_rounded,
                  loading: _saving,
                  onPressed: _saving ? null : () => unawaited(_save()),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ...people.when(
          loading: () => <Widget>[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
          error: (Object e, _) => <Widget>[
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    ErrorPresenter.messageOf(e),
                    key: const Key('admin.people.loadError'),
                    style: TextStyle(color: tokens.errorText),
                  ),
                  TextButton(
                    key: const Key('admin.people.retry'),
                    onPressed: () => ref.invalidate(adminPersonLinksProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
          data: (PersonLinksDto data) => <Widget>[
            Text(
              data.people.isEmpty
                  ? 'لا يوجد شخص مربوط'
                  : 'أشخاص مربوطون: ${data.people.length}',
              key: const Key('admin.people.summary'),
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final LinkedPersonDto person in data.people)
              _PersonCard(
                key: Key('admin.people.person.${person.mainId}'),
                person: person,
                onEdit: () => _edit(person),
                onUnlink: () => unawaited(_unlink(person)),
              ),
          ],
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.user,
    required this.role,
    required this.onChoose,
    this.onDrop,
    this.roleKey = 'role',
  });

  /// Keys the role chips apart: `role` in the search results, `draftRole`
  /// in the person being set.
  final String roleKey;
  final UserSummaryDto user;
  final PersonRole? role;
  final ValueChanged<PersonRole> onChoose;
  final VoidCallback? onDrop;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
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
              _name(user),
              style: context.text.bodyLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              user.email ?? user.id,
              style: context.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                for (final PersonRole option in PersonRole.values)
                  ChoiceChip(
                    key: Key('admin.people.$roleKey.${user.id}.${option.name}'),
                    label: Text(_roleLabel(option)),
                    selected: role == option,
                    onSelected: (_) => onChoose(option),
                  ),
                if (onDrop != null)
                  IconButton(
                    key: Key('admin.people.drop.${user.id}'),
                    tooltip: 'إزالة من الشخص',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onDrop,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    super.key,
    required this.person,
    required this.onEdit,
    required this.onUnlink,
  });

  final LinkedPersonDto person;
  final VoidCallback onEdit;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final LinkedAccountDto account in person.accounts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${_name(account.user)} · '
                  '${account.user.id == person.mainId ? 'أساسي' : (account.counted ? 'ثانٍ' : 'مخفي')}',
                  key: Key('admin.people.account.${account.user.id}'),
                  style: context.text.bodyMedium?.copyWith(
                    color: account.counted
                        ? tokens.textPrimary
                        : tokens.textSecondary,
                    fontWeight: account.user.id == person.mainId
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                AdminSecondaryButton(
                  key: Key('admin.people.edit.${person.mainId}'),
                  label: 'تعديل',
                  icon: Icons.edit_rounded,
                  onPressed: onEdit,
                ),
                AdminSecondaryButton(
                  key: Key('admin.people.unlink.${person.mainId}'),
                  label: 'فك الربط',
                  icon: Icons.link_off_rounded,
                  onPressed: onUnlink,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
