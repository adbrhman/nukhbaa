/// قسم «المخفيون» في لوحة المشرف (السكربت 259، قرار المالك 2026-11-11):
/// المشرف المالك وحده يخفي أي حساب من كل اللوحات، وأولها حساب مراجعة
/// Google Play.
///
/// الحساب المخفي يدخل ويتوقع وتصله إشعاراته كأي لاعب، لكنه لا يُحسب في أي
/// ترتيب ولا في قرعة المواجهات ولا كأس النخبة ولا التتويج (الهجرة 0207).
/// والإظهار يعيد نقاطه كما هي، فلا يُحذف شيء.
///
/// التبويب لا يظهر إلا لحساب المالك (`ownerAdminEmail`)؛ والخادم يرفض أي
/// مشرف آخر في كل حال (`admin.owner_only`).
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
import '../../../auth/session_state.dart';
import '../../widgets/admin_ui_kit.dart';

/// The owner admin's e-mail: the one account that sees this tab, as the
/// server's owner (`OwnerNotices`) is found by it.
const String ownerAdminEmail = 'adbrhmanm@gmail.com';

/// Whether [session] is the owner admin's.
bool isOwnerAdminSession(SessionState? session) => switch (session) {
  SessionAuthenticated(:final user) =>
    user.role == 'admin' &&
        (user.email ?? '').trim().toLowerCase() == ownerAdminEmail,
  _ => false,
};

/// `GET /admin/hidden-accounts`.
final adminHiddenAccountsProvider =
    FutureProvider.autoDispose<HiddenAccountsDto>((ref) async {
      return switch (await ref.watch(adminApiProvider).hiddenAccounts()) {
        Ok<HiddenAccountsDto>(:final value) => value,
        Err<HiddenAccountsDto>(:final error) => throw error,
      };
    });

String _name(UserSummaryDto user) =>
    user.displayName.isEmpty ? (user.email ?? user.id) : user.displayName;

/// The owner admin's "hidden accounts" tab.
class HiddenAccountsSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const HiddenAccountsSection({super.key});

  @override
  ConsumerState<HiddenAccountsSection> createState() =>
      _HiddenAccountsSectionState();
}

class _HiddenAccountsSectionState extends ConsumerState<HiddenAccountsSection> {
  final TextEditingController _search = TextEditingController();
  List<UserSummaryDto>? _found;
  bool _searching = false;
  String? _busyId;
  String? _error;

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

  Future<void> _set(UserSummaryDto user, {required bool hidden}) async {
    setState(() {
      _busyId = user.id;
      _error = null;
    });
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .setAccountHidden(user.id, hidden: hidden);
    if (!mounted) return;
    setState(() => _busyId = null);
    switch (result) {
      case Ok<bool>():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hidden
                  ? 'أُخفي «${_name(user)}» من كل اللوحات'
                  : 'ظهر «${_name(user)}» ونقاطه في اللوحات',
            ),
          ),
        );
        ref.invalidate(adminHiddenAccountsProvider);
      case Err<bool>(:final error):
        setState(() => _error = ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<HiddenAccountsDto> hidden = ref.watch(
      adminHiddenAccountsProvider,
    );
    final Set<String> hiddenIds = <String>{
      for (final HiddenAccountDto a
          in hidden.value?.accounts ?? const <HiddenAccountDto>[])
        a.user.id,
    };
    final String? error = _error;
    final List<UserSummaryDto>? found = _found;
    return ListView(
      key: const Key('admin.hidden.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'الحسابات المخفية',
          subtitle:
              'الحساب المخفي يدخل ويتوقع كأي لاعب، لكنه لا يظهر في أي '
              'ترتيب ولا يدخل قرعة المواجهات ولا التتويج. الإظهار يعيد '
              'نقاطه كما هي. هذا القسم لك وحدك.',
        ),
        ...hidden.when(
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
                    key: const Key('admin.hidden.loadError'),
                    style: TextStyle(color: tokens.errorText),
                  ),
                  TextButton(
                    key: const Key('admin.hidden.retry'),
                    onPressed: () =>
                        ref.invalidate(adminHiddenAccountsProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
          data: (HiddenAccountsDto data) => <Widget>[
            Text(
              data.accounts.isEmpty
                  ? 'لا يوجد حساب مخفي'
                  : 'حسابات مخفية: ${data.accounts.length}',
              key: const Key('admin.hidden.summary'),
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final HiddenAccountDto account in data.accounts)
              _AccountRow(
                key: Key('admin.hidden.account.${account.user.id}'),
                user: account.user,
                hidden: true,
                busy: _busyId == account.user.id,
                onPressed: _busyId != null
                    ? null
                    : () => unawaited(_set(account.user, hidden: false)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'إخفاء حساب',
                style: context.text.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminTextField(
                key: const Key('admin.hidden.searchField'),
                controller: _search,
                hint: 'الاسم أو البريد',
                prefixIcon: Icons.search_rounded,
                enabled: !_searching,
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminSecondaryButton(
                key: const Key('admin.hidden.search'),
                label: 'بحث',
                icon: Icons.search_rounded,
                loading: _searching,
                onPressed: _searching ? null : () => unawaited(_find()),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  error,
                  key: const Key('admin.hidden.error'),
                  style: TextStyle(color: tokens.errorText),
                ),
              ],
              if (found != null && found.isEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'لا يوجد لاعب بهذا الاسم أو البريد',
                  key: Key('admin.hidden.none'),
                ),
              ],
              for (final UserSummaryDto user
                  in found ?? const <UserSummaryDto>[])
                if ((user.email ?? '').trim().toLowerCase() != ownerAdminEmail)
                  _AccountRow(
                    key: Key('admin.hidden.found.${user.id}'),
                    user: user,
                    hidden: hiddenIds.contains(user.id),
                    busy: _busyId == user.id,
                    onPressed: _busyId != null
                        ? null
                        : () => unawaited(
                            _set(user, hidden: !hiddenIds.contains(user.id)),
                          ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.user,
    required this.hidden,
    required this.busy,
    required this.onPressed,
  });

  final UserSummaryDto user;
  final bool hidden;
  final bool busy;
  final VoidCallback? onPressed;

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
              hidden
                  ? '${user.email ?? user.id} · مخفي'
                  : user.email ?? user.id,
              style: context.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (hidden)
              AdminSecondaryButton(
                key: Key('admin.hidden.show.${user.id}'),
                label: 'إظهار',
                icon: Icons.visibility_rounded,
                loading: busy,
                onPressed: onPressed,
              )
            else
              AdminPrimaryButton(
                key: Key('admin.hidden.hide.${user.id}'),
                label: 'إخفاء',
                icon: Icons.visibility_off_rounded,
                loading: busy,
                onPressed: onPressed,
              ),
          ],
        ),
      ),
    );
  }
}
