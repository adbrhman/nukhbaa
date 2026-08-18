library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/ui/ui.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/widgets/async_list_view.dart';
import '../../admin_providers.dart';

class UserSanctionSection extends ConsumerStatefulWidget {
  const UserSanctionSection({super.key});

  @override
  ConsumerState<UserSanctionSection> createState() =>
      _UserSanctionSectionState();
}

class _UserSanctionSectionState extends ConsumerState<UserSanctionSection> {
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    _reasonController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    ref
        .read(usersLookupControllerProvider.notifier)
        .search(_searchController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<UserSanctionResultDto>? state = ref.watch(
      userSanctionControllerProvider,
    );
    final AsyncValue<UserListDto>? search = ref.watch(
      usersLookupControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<UserSanctionResultDto>;
    final bool searching = search is AsyncLoading<UserListDto>;
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  fieldKey: const Key('admin.users.searchField'),
                  controller: _searchController,
                  label: l10n.adminUsersSearchLabel,
                  enabled: !searching,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 120,
                child: AppButton(
                  key: const Key('admin.users.searchButton'),
                  label: l10n.adminLookUpButton,
                  onPressed: searching ? null : _search,
                  loading: searching,
                ),
              ),
            ],
          ),
          if (search != null)
            SizedBox(
              height: 200,
              child: AsyncListView<UserSummaryDto>(
                value: search.whenData((dto) => dto.users),
                emptyMessage: l10n.adminUsersEmptyResults,
                onRetry: _search,
                itemBuilder: (context, user) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    key: Key('admin.users.result.${user.id}'),
                    onTap: () =>
                        setState(() => _userIdController.text = user.id),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(user.email ?? user.id),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                user.status,
                                style: TextStyle(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            fieldKey: const Key('admin.users.userIdField'),
            controller: _userIdController,
            label: l10n.userId,
            enabled: !inFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            fieldKey: const Key('admin.users.reasonField'),
            controller: _reasonController,
            label: l10n.adminReasonMandatoryLabel,
            enabled: !inFlight,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state is AsyncError<UserSanctionResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                ErrorPresenter.message(state.error as AppError),
                key: const Key('admin.users.error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
          if (state is AsyncData<UserSanctionResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                l10n.adminSanctionResultMessage(
                  state.value.userId,
                  state.value.status,
                ),
                key: const Key('admin.users.result'),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  key: const Key('admin.users.suspend'),
                  label: l10n.adminSuspendButton,
                  variant: AppButtonVariant.secondary,
                  onPressed: inFlight ? null : () => _act(suspend: true),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  key: const Key('admin.users.reinstate'),
                  label: l10n.adminReinstateButton,
                  onPressed: inFlight ? null : () => _act(suspend: false),
                  loading: inFlight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _act({required bool suspend}) {
    final userId = _userIdController.text.trim();
    final reason = _reasonController.text.trim();
    if (userId.isEmpty || reason.isEmpty) return;
    final notifier = ref.read(userSanctionControllerProvider.notifier);
    if (suspend) {
      notifier.suspend(userId, reason);
    } else {
      notifier.reinstate(userId, reason);
    }
  }
}
