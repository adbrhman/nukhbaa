library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'hall_of_fame_providers.dart';

/// The platform-wide, all-time standings — every user's total points summed
/// across every season they have played.
class HallOfFameScreen extends ConsumerWidget {
  const HallOfFameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<HallOfFameDto> board = ref.watch(hallOfFameProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.hallOfFame, key: const Key('hallOfFame.title')),
      ),
      body: AsyncListView(
        value: board.whenData((dto) => dto.entries),
        emptyMessage: l10n.hallOfFameEmpty,
        onRetry: () => ref.invalidate(hallOfFameProvider),
        itemBuilder: (context, entry) => _HallOfFameRow(entry: entry),
      ),
    );
  }
}

class _HallOfFameRow extends StatelessWidget {
  const _HallOfFameRow({required this.entry});
  final HallOfFameEntryDto entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return ListTile(
      key: Key('hallOfFame.item.${entry.userId}'),
      leading: CircleAvatar(
        child: Text(
          '${entry.rank}',
          key: Key('hallOfFame.rank.${entry.userId}'),
        ),
      ),
      title: Text(
        entry.displayName,
        key: Key('hallOfFame.user.${entry.userId}'),
        style: text.bodyLarge?.copyWith(color: tokens.textPrimary),
      ),
      subtitle: Text(
        l10n.hallOfFameSeasonsPlayed(entry.seasonsPlayed),
        key: Key('hallOfFame.seasonsPlayed.${entry.userId}'),
        style: text.bodySmall?.copyWith(color: tokens.textSecondary),
      ),
      trailing: Text(
        l10n.pointsAbbreviated(entry.totalPoints),
        key: Key('hallOfFame.points.${entry.userId}'),
        style: text.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: tokens.primary,
        ),
      ),
    );
  }
}
