library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../competition/widgets/async_list_view.dart';
import 'ledger_providers.dart';

/// Shows the caller's own current balance plus their append-only points
/// history, for a given [participantId].
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({required this.participantId, super.key});
  final String participantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BalanceDto> balance = ref.watch(
      participantBalanceProvider(participantId),
    );
    final AsyncValue<ParticipantEntriesDto> entries = ref.watch(
      participantEntriesProvider(participantId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('My Points', key: Key('ledger.title'))),
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
              emptyMessage: 'No points movements yet.',
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      color: AppColors.surfaceElevated,
      child: Column(
        children: <Widget>[
          Text(
            '${balance.balance}',
            key: const Key('ledger.balance'),
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${balance.entryCount} movements counted',
            key: const Key('ledger.entryCount'),
            style: const TextStyle(color: AppColors.textSecondary),
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
    final bool negative = entry.amount < 0;
    return ListTile(
      key: Key('ledger.entry.${entry.id}'),
      leading: Icon(
        entry.kind == 'correction'
            ? Icons.build_outlined
            : Icons.emoji_events_outlined,
        color: AppColors.textSecondary,
      ),
      title: Text(entry.kind, key: Key('ledger.entry.kind.${entry.id}')),
      subtitle: Text(
        entry.occurredAt,
        key: Key('ledger.entry.occurredAt.${entry.id}'),
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: Text(
        '${negative ? '' : '+'}${entry.amount}',
        key: Key('ledger.entry.amount.${entry.id}'),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: negative ? Colors.redAccent : AppColors.primary,
        ),
      ),
    );
  }
}
