library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'ledger_providers.dart';

/// Shows the caller's own current balance plus their append-only points
/// history, for a given [participantId].
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({required this.participantId, super.key});
  final String participantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<BalanceDto> balance = ref.watch(
      participantBalanceProvider(participantId),
    );
    final AsyncValue<ParticipantEntriesDto> entries = ref.watch(
      participantEntriesProvider(participantId),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ledgerTitle, key: const Key('ledger.title'))),
      body: Column(
        children: <Widget>[
          AsyncObjectView<BalanceDto>(
            value: balance,
            onRetry: () =>
                ref.invalidate(participantBalanceProvider(participantId)),
            builder: (context, dto) => _BalanceHeader(balance: dto),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncListView<PointEntryDto>(
              value: entries.whenData((e) => e.entries),
              emptyMessage: l10n.ledgerEmpty,
              onRetry: () =>
                  ref.invalidate(participantEntriesProvider(participantId)),
              itemBuilder: (context, entry) => _EntryRow(entry: entry),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.balance});
  final BalanceDto balance;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      color: tokens.surfaceElevated,
      child: Column(
        children: <Widget>[
          Text(
            '${balance.balance}',
            key: const Key('ledger.balance'),
            style: text.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: tokens.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.ledgerEntryCount(balance.entryCount),
            key: const Key('ledger.entryCount'),
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final PointEntryDto entry;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final bool negative = entry.amount < 0;
    return ListTile(
      key: Key('ledger.entry.${entry.id}'),
      leading: Icon(
        entry.kind == 'correction'
            ? Icons.build_outlined
            : Icons.emoji_events_outlined,
        color: tokens.textSecondary,
      ),
      title: Text(entry.kind, key: Key('ledger.entry.kind.${entry.id}')),
      subtitle: Text(
        entry.occurredAt,
        key: Key('ledger.entry.occurredAt.${entry.id}'),
        style: TextStyle(color: tokens.textSecondary),
      ),
      trailing: Text(
        '${negative ? '' : '+'}${entry.amount}',
        key: Key('ledger.entry.amount.${entry.id}'),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: negative ? tokens.error : tokens.primary,
        ),
      ),
    );
  }
}
