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
import '../../admin_providers.dart';

class LedgerLookupSection extends ConsumerStatefulWidget {
  const LedgerLookupSection({super.key});

  @override
  ConsumerState<LedgerLookupSection> createState() =>
      _LedgerLookupSectionState();
}

class _LedgerLookupSectionState extends ConsumerState<LedgerLookupSection> {
  final TextEditingController _participantIdController =
      TextEditingController();

  @override
  void dispose() {
    _participantIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<ParticipantEntriesDto>? state = ref.watch(
      adminLedgerLookupControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<ParticipantEntriesDto>;
    final AppTokens tokens = context.tokens;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  fieldKey: const Key('admin.ledger.participantIdField'),
                  controller: _participantIdController,
                  label: l10n.adminParticipantIdLabel,
                  enabled: !inFlight,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 120,
                child: AppButton(
                  key: const Key('admin.ledger.lookup'),
                  label: l10n.adminLookUpButton,
                  loading: inFlight,
                  onPressed: inFlight
                      ? null
                      : () {
                          final id = _participantIdController.text.trim();
                          if (id.isEmpty) return;
                          ref
                              .read(
                                adminLedgerLookupControllerProvider.notifier,
                              )
                              .lookup(id);
                        },
                ),
              ),
            ],
          ),
        ),
        if (state is AsyncLoading<ParticipantEntriesDto>)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: CircularProgressIndicator(),
          ),
        if (state is AsyncError<ParticipantEntriesDto>)
          Expanded(
            child: AppErrorState(
              key: const Key('admin.ledger.error'),
              message: ErrorPresenter.message(state.error as AppError),
              onRetry: () {
                final id = _participantIdController.text.trim();
                if (id.isEmpty) return;
                ref
                    .read(adminLedgerLookupControllerProvider.notifier)
                    .lookup(id);
              },
            ),
          ),
        if (state is AsyncData<ParticipantEntriesDto>)
          Expanded(
            child: state.value.entries.isEmpty
                ? AppEmptyState(title: l10n.adminUsersEmptyResults)
                : ListView.separated(
                    key: const Key('admin.ledger.list'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    itemCount: state.value.entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = state.value.entries[index];
                      return AppCard(
                        key: Key('admin.ledger.item.${entry.id}'),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    entry.kind,
                                    key: Key('admin.ledger.kind.${entry.id}'),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    entry.occurredAt,
                                    key: Key(
                                      'admin.ledger.occurredAt.${entry.id}',
                                    ),
                                    style: TextStyle(color: tokens.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${entry.amount}',
                              key: Key('admin.ledger.amount.${entry.id}'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
