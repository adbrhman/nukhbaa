library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_card.dart';
import '../../l10n/app_localizations.dart';
import 'groups_providers.dart';

/// A name-only form that creates a new private group owned by the caller,
/// then surfaces the server-generated invite code so it can be shared.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _copyInviteCode(String code) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.inviteCodeCopiedMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<GroupDto>? state = ref.watch(
      createGroupControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<GroupDto>;
    final AppTokens tokens = context.tokens;

    if (state is AsyncData<GroupDto>) {
      final GroupDto group = state.value;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.groupCreatedTitle)),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                group.name,
                key: const Key('createGroup.successName'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.groupInviteCodeHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        group.inviteCode,
                        key: const Key('createGroup.successCode'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: tokens.primary,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      key: const Key('createGroup.copyButton'),
                      icon: Icon(Icons.copy_outlined, color: tokens.primary),
                      tooltip: l10n.copyInviteCodeButton,
                      onPressed: () => _copyInviteCode(group.inviteCode),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                key: const Key('createGroup.doneButton'),
                onPressed: () => Navigator.of(context).pop(group),
                child: Text(l10n.doneButton),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createGroupTitle, key: const Key('createGroup.title')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const Key('createGroup.nameField'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.groupNameLabel,
                border: const OutlineInputBorder(),
              ),
              enabled: !inFlight,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state is AsyncError<GroupDto>)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  ErrorPresenter.message(state.error as AppError),
                  key: const Key('createGroup.error'),
                  style: TextStyle(color: tokens.error),
                ),
              ),
            FilledButton(
              key: const Key('createGroup.submit'),
              onPressed: inFlight
                  ? null
                  : () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;
                      ref
                          .read(createGroupControllerProvider.notifier)
                          .create(name);
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
                  : Text(l10n.createGroupButton),
            ),
          ],
        ),
      ),
    );
  }
}
