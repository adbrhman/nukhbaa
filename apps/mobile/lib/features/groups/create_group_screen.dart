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

/// A name-only form that creates a new private group owned by the caller.
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<GroupDto>? state = ref.watch(
      createGroupControllerProvider,
    );
    ref.listen<AsyncValue<GroupDto>?>(createGroupControllerProvider, (
      previous,
      next,
    ) {
      if (next is AsyncData<GroupDto>) {
        Navigator.of(context).pop(next.value);
      }
    });
    final bool inFlight = state is AsyncLoading<GroupDto>;
    final AppTokens tokens = context.tokens;
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
