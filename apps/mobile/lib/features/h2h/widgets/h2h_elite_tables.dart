/// ترتيب مجموعات النخبة الأربع للاعب (2026-11-08): يختار المجموعة من أزرار
/// الأرقام، فيرى جدولها بالأعمدة المسمّاة، ويشارك صورتها أو صورة المجموعات
/// الأربع معاً.
///
/// كل رقم وكل مركز من الخادم (`GET /me/h2h-league/elite`): هنا لا يُرتَّب
/// شيء ولا يُجمع. تُفتح المجموعة التي فيها اللاعب إن كان في النخبة، وإلا
/// الأولى.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/segmented_pills.dart';
import '../h2h_providers.dart';
import '../h2h_texts.dart';
import 'h2h_share_cards.dart';
import 'h2h_standings_table.dart';

/// مجموعات النخبة.
class H2hEliteTables extends ConsumerStatefulWidget {
  /// ينشئ العرض.
  const H2hEliteTables({super.key});

  @override
  ConsumerState<H2hEliteTables> createState() => _H2hEliteTablesState();
}

class _H2hEliteTablesState extends ConsumerState<H2hEliteTables> {
  /// المجموعة التي اختارها اللاعب، أو null قبل أن يختار.
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<H2hAdminGroupsDto> value = ref.watch(
      h2hEliteTablesProvider,
    );
    return value.when(
      skipLoadingOnRefresh: false,
      loading: () => const Padding(
        key: Key('h2h.elite.loading'),
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) =>
          _Failed(onRetry: () => ref.invalidate(h2hEliteTablesProvider)),
      data: (H2hAdminGroupsDto data) => _body(context, data),
    );
  }

  Widget _body(BuildContext context, H2hAdminGroupsDto data) {
    final AppTokens t = context.tokens;
    final List<H2hAdminGroupDto> elite = h2hEliteGroupsOf(data);
    if (elite.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text(
          'تظهر مجموعات النخبة بعد قرعة الشهر.',
          key: const Key('h2h.elite.empty'),
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
        ),
      );
    }
    final int mine = elite.indexWhere(
      (H2hAdminGroupDto g) => g.standings.any((H2hStandingDto s) => s.isMe),
    );
    final int selected = (_picked ?? (mine < 0 ? 0 : mine)).clamp(
      0,
      elite.length - 1,
    );
    final H2hAdminGroupDto group = elite[selected];
    final String title = h2hGroupTitle(
      data.monthStart,
      group.division,
      group.groupIndex,
    );
    final String month = h2hMonthLabel(data.monthStart);
    return Column(
      key: const Key('h2h.elite'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'اختر المجموعة',
          style: context.text.labelMedium?.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        SegmentedPills(
          key: const Key('h2h.elite.groups'),
          labels: <String>[
            for (final H2hAdminGroupDto g in elite)
              '${h2hGroupNumber(g.division, g.groupIndex)}',
          ],
          selectedIndex: selected,
          keyPrefix: 'h2h.elite.group',
          onSelected: (int index) => setState(() => _picked = index),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                key: const Key('h2h.elite.title'),
                style: context.text.titleSmall?.copyWith(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (selected == mine)
              Text(
                'مجموعتك',
                key: const Key('h2h.elite.mine'),
                style: context.text.labelMedium?.copyWith(
                  color: t.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        H2hStandingsTable(
          standings: group.standings,
          promotionZone: group.promotionZone,
          relegationZone: group.relegationZone,
          eliteDraw: true,
          keyPrefix: 'h2h.elite.table',
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          key: const Key('h2h.elite.shareGroup'),
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('صورة ترتيب هذه المجموعة'),
          onPressed: group.standings.isEmpty
              ? null
              : () => unawaited(
                  showH2hStandingsShare(
                    context,
                    heading: 'ترتيب دوري المواجهات',
                    subheading: '$title · $month',
                    groups: <H2hShareStandings>[
                      h2hShareStandingsOf(data.monthStart, group),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('h2h.elite.shareAll'),
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('صورة المجموعات الأربع'),
          onPressed: () => unawaited(
            showH2hStandingsShare(
              context,
              heading: 'ترتيب دوري المواجهات',
              subheading: 'مجموعات النخبة · $month',
              groups: <H2hShareStandings>[
                for (final H2hAdminGroupDto g in elite)
                  h2hShareStandingsOf(data.monthStart, g),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// تعذّر التحميل.
class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      key: const Key('h2h.elite.failed'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Text(
            'تعذّر تحميل مجموعات النخبة.',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            key: const Key('h2h.elite.retry'),
            onPressed: onRetry,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
