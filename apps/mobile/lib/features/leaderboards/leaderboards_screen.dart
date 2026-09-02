import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/rank_badge.dart';
import '../competition/competition_providers.dart';
import '../competition/widgets/async_list_view.dart';
import 'leaderboards_providers.dart';

/// Discovery entry point for leaderboards. It uses the caller's active seasons
/// as the server-backed scope and reuses the same season leaderboard provider
/// as the contextual board opened from a fixture.
class LeaderboardsScreen extends ConsumerWidget {
  const LeaderboardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final seasons = ref.watch(activeSeasonsProvider);
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: const Text('المتصدرون'),
        backgroundColor: tokens.background,
      ),
      body: seasons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            'تعذر تحميل المواسم النشطة.',
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'انضم إلى موسم لتظهر ترتيباتك هنا.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
            );
          }
          return DefaultTabController(
            length: items.length,
            child: Column(
              children: <Widget>[
                TabBar(
                  isScrollable: true,
                  tabs: items
                      .map(
                        (season) => Tab(
                          key: Key('leaderboards.season.${season.seasonId}'),
                          text:
                              '${season.competitionName} · ${season.seasonLabel}',
                        ),
                      )
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: items
                        .map(
                          (season) => _SeasonLeaderboard(
                            seasonId: season.seasonId,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SeasonLeaderboard extends ConsumerWidget {
  const _SeasonLeaderboard({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(seasonLeaderboardProvider(seasonId));
    return AsyncListView<LeaderboardEntryDto>(
      value: standings.whenData((board) => board.entries),
      emptyMessage: 'لا توجد نتائج مسجلة لهذا الموسم بعد.',
      onRetry: () => ref.invalidate(seasonLeaderboardProvider(seasonId)),
      itemBuilder: (context, entry) => ListTile(
        key: Key('leaderboards.item.${entry.participantId}'),
        leading: RankBadge(rank: entry.rank),
        title: Text(
          entry.participantId,
          style: TextStyle(color: context.tokens.textPrimary),
        ),
        subtitle: Text('${entry.entryCount} مشاركة'),
        trailing: Text(
          '${entry.totalPoints}',
          style: TextStyle(
            color: context.tokens.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}