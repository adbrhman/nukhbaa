library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import 'groups_providers.dart';

/// An invite-code-only form that joins the caller into a private group.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<GroupMembershipDto>? state = ref.watch(
      joinGroupControllerProvider,
    );
    ref.listen<AsyncValue<GroupMembershipDto>?>(joinGroupControllerProvider, (
      previous,
      next,
    ) {
      if (next is AsyncData<GroupMembershipDto>) {
        Navigator.of(context).pop(next.value);
      }
    });
    final bool inFlight = state is AsyncLoading<GroupMembershipDto>;
    final AppTokens tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.joinGroupTitle, key: const Key('joinGroup.title')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const Key('joinGroup.codeField'),
              controller: _codeController,
              decoration: InputDecoration(
                labelText: l10n.inviteCodeLabel,
                border: const OutlineInputBorder(),
              ),
              enabled: !inFlight,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state is AsyncError<GroupMembershipDto>)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  ErrorPresenter.message(state.error as AppError),
                  key: const Key('joinGroup.error'),
                  style: TextStyle(color: tokens.error),
                ),
              ),
            FilledButton(
              key: const Key('joinGroup.submit'),
              onPressed: inFlight
                  ? null
                  : () {
                      final code = _codeController.text.trim();
                      if (code.isEmpty) return;
                      ref.read(joinGroupControllerProvider.notifier).join(code);
                    },
              child: inFlight
                  ? SizedBox(
                      width: AppSizes.progressSm,
                      height: AppSizes.progressSm,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.onPrimary,
                      ),
                    )
                  : Text(l10n.joinGroupButton),
            ),
          ],
        ),
      ),
    );
  }
}
