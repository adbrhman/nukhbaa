library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/format/timestamps.dart';
import '../admin_providers.dart';
import '../screens/sections/admin_home_section.dart';
import 'admin_ui_kit.dart';

/// «بانتظار النتيجة» atop النتائج والاحتساب (2026-10-08): the month's real
/// matches that are over with no result -- the very list the home page and
/// the menu count ([fixturesAwaitingResult]) -- each filling the form below
/// with its league, month and match. Nothing shows when none waits.
class AdminAwaitingResults extends ConsumerWidget {
  const AdminAwaitingResults({super.key, required this.onPick, this.now});

  /// Called with the tapped match.
  final ValueChanged<CurrentMonthFixtureItemDto> onPick;

  /// The clock; null reads the real time.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final List<CurrentMonthFixtureItemDto> items = switch (ref.watch(
      adminDashboardProvider,
    )) {
      AsyncData<AdminDashboardSnapshot>(:final value) => fixturesAwaitingResult(
        value.currentMonthFixtures,
        (now ?? DateTime.now)(),
      ),
      _ => const <CurrentMonthFixtureItemDto>[],
    };
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AdminCard(
        key: const Key('admin.results.awaiting'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSectionHeader(
              title: 'بانتظار النتيجة (${items.length})',
              subtitle: 'اضغط مباراة لتعبئة النموذج بها',
            ),
            for (final CurrentMonthFixtureItemDto item in items)
              // A ListTile paints its ink on the nearest Material; the card's
              // own background would hide it.
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: Key('admin.results.awaiting.${item.fixture.fixtureId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.scoreboard_rounded, color: t.gold),
                  title: Text(
                    '${item.fixture.homeTeam ?? 'غير محدد'} × '
                    '${item.fixture.awayTeam ?? 'غير محدد'}',
                    style: context.text.bodyMedium?.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    item.fixture.kickoffAt == null
                        ? 'موعد غير محدد'
                        : formatTimestamp(context, item.fixture.kickoffAt!),
                    style: context.text.bodySmall?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                  onTap: () => onPick(item),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
