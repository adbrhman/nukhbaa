library;
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../competition/widgets/async_list_view.dart';
import 'hall_of_fame_providers.dart';

/// The platform-wide, all-time standings — every user's total points summed
/// across every season they have played.
class HallOfFameScreen extends ConsumerWidget {
  const HallOfFameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HallOfFameDto> board = ref.watch(hallOfFameProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Hall of Fame', key: Key('hallOfFame.title'))),
      body: AsyncListView<HallOfFameEntryDto>(
        value: board.whenData((dto) => dto.entries),
        emptyMessage: 'Nobody has earned any points yet.',
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
    return ListTile(
      key: Key('hallOfFame.item.${entry.userId}'),
      leading: CircleAvatar(child: Text('${entry.rank}', key: Key('hallOfFame.rank.${entry.userId}'))),
      title: Text(entry.userId, key: Key('hallOfFame.user.${entry.userId}'), style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text('${entry.seasonsPlayed} seasons played', key: Key('hallOfFame.seasonsPlayed.${entry.userId}'), style: const TextStyle(color: AppColors.textSecondary)),
      trailing: Text('${entry.totalPoints} pts', key: Key('hallOfFame.points.${entry.userId}'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
    );
  }
}
