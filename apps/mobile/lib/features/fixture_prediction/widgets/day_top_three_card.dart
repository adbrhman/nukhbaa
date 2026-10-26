/// The day's three most points (owner's request 2026-10-25): the first
/// three players of the day's standings, by the server's own board -- the
/// same `GET /seasons/{id}/fixture-leaderboard?from=&to=` read as the
/// leaderboard's "اليوم" tab, so the ranks, the points and the tie-breaks
/// can never differ from it. A player with no points that day is left out.
///
/// Admins only: the predictions board names the three above the table, and
/// the line opens a card to share. The card is drawn on screen, captured
/// exactly as seen and handed to the system share sheet (`share_plus`),
/// with the admin's invitation link in the text, like the hero card
/// (`day_hero_card.dart`).
///
/// Nothing is ranked or totalled here.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/web_links.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/share_picture.dart';
import '../../auth/sign_in_screen.dart' show kBrandLogoAsset;
import 'day_hero_card.dart' show pointsText;

// A picture that leaves the app keeps the brand's dark colours whatever
// theme the admin runs, read from AppColors so it cannot drift.
const Color _navy = AppColors.background;
const Color _navyRaised = AppColors.surface;
const Color _gold = AppColors.gold;
const Color _white = AppColors.textPrimary;
const Color _muted = AppColors.textMuted;

/// How many players the card ranks.
const int dayTopThreeSize = 3;

/// One of the three.
final class DayTopEntry {
  /// Creates the line for [playerName], placed [rank] with [points].
  const DayTopEntry({
    required this.participantId,
    required this.rank,
    required this.playerName,
    required this.points,
  });

  /// The player's participant id.
  final String participantId;

  /// The server's rank (a shared rank stays shared).
  final int rank;

  /// The player's display name.
  final String playerName;

  /// The player's points that day, as the server summed them.
  final int points;
}

/// The facts one card shows.
final class DayTopThree {
  /// Creates the facts for [day]'s [entries].
  const DayTopThree({required this.day, required this.entries});

  /// The Riyadh day ranked (a day key).
  final DateTime day;

  /// The players, in the server's order; one to three, never empty.
  final List<DayTopEntry> entries;
}

/// The first three of [board] with points, in the server's order; null
/// while the board is unknown or when nobody scored that [day]. [unnamed]
/// stands for a player without a name.
DayTopThree? dayTopThreeOf(
  FixtureLeaderboardDto? board, {
  required DateTime day,
  required String unnamed,
}) {
  if (board == null) return null;
  final List<DayTopEntry> entries = <DayTopEntry>[
    for (final FixtureLeaderboardEntryDto e in board.entries)
      if (e.totalPoints > 0)
        DayTopEntry(
          participantId: e.participantId,
          rank: e.rank,
          playerName: e.displayName.isEmpty ? unnamed : e.displayName,
          points: e.totalPoints,
        ),
  ].take(dayTopThreeSize).toList(growable: false);
  if (entries.isEmpty) return null;
  return DayTopThree(day: day, entries: entries);
}

const List<String> _weekdays = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const List<String> _months = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// [day] in Arabic, the way the leaderboard prints it: السبت 24 أكتوبر 2026.
String dayTopThreeDateLabel(DateTime day) =>
    '${_weekdays[day.weekday - 1]} ${day.day} '
    '${_months[day.month - 1]} ${day.year}';

/// The share text: the day, each player with his points, and the site's
/// link.
String dayTopThreeShareText(DayTopThree top) {
  final StringBuffer text = StringBuffer(
    'الأكثر نقاطاً في النخبة · ${dayTopThreeDateLabel(top.day)}',
  );
  for (final DayTopEntry e in top.entries) {
    text.write('\n${e.rank}. ${e.playerName} · ${pointsText(e.points)}');
  }
  text.write('\nشاركنا في نُخبة: ${appSiteLink()}');
  return text.toString();
}

/// Opens the card for [top] with its share and close actions.
Future<void> showDayTopThreeCard(BuildContext context, DayTopThree top) =>
    showDialog<void>(
      context: context,
      builder: (_) => DayTopThreeShareDialog(top: top),
    );

/// An admin's line above the board: the day's three most points, and a way
/// to the card.
class DayTopThreeBanner extends StatelessWidget {
  /// Creates the line for [top].
  const DayTopThreeBanner({required this.top, super.key});

  /// The three.
  final DayTopThree top;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Material(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brButton,
        child: InkWell(
          key: const Key('fixturePredictions.topThree'),
          borderRadius: AppRadius.brButton,
          onTap: () => unawaited(showDayTopThreeCard(context, top)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.leaderboard_rounded,
                  size: AppSizes.iconSm,
                  color: tokens.goldAccent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'الأكثر نقاطاً اليوم: '
                    '${top.entries.map((e) => e.playerName).join(' · ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: AppFontSize.s12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.ios_share_rounded,
                  size: AppSizes.iconSm,
                  color: tokens.primaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The preview of the card, with the share and close actions.
class DayTopThreeShareDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for [top].
  const DayTopThreeShareDialog({required this.top, super.key});

  /// What the card shows.
  final DayTopThree top;

  @override
  ConsumerState<DayTopThreeShareDialog> createState() =>
      _DayTopThreeShareDialogState();
}

class _DayTopThreeShareDialogState
    extends ConsumerState<DayTopThreeShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;
  bool _shareFailed = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RepaintBoundary(
              key: _cardKey,
              child: DayTopThreeCard(top: widget.top),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('dayTopThree.share'),
                    onPressed: _sharing ? null : () => unawaited(_share()),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('مشاركة البطاقة'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  key: const Key('dayTopThree.close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
            if (_shareFailed) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                sharePictureFailedText,
                key: const Key('dayTopThree.failed'),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.tokens.errorText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    setState(() {
      _sharing = true;
      _shareFailed = false;
    });
    try {
      final bool shared = await sharePicture(
        boundaryKey: _cardKey,
        text: dayTopThreeShareText(widget.top),
        fileName: 'nukhba-top-three.png',
      );
      if (mounted && !shared) setState(() => _shareFailed = true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// The picture itself: the day, then the three with their points.
class DayTopThreeCard extends StatelessWidget {
  /// Creates the card for [top].
  const DayTopThreeCard({required this.top, super.key});

  /// What the card shows.
  final DayTopThree top;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('dayTopThree.card'),
      width: 340,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: AppRadius.brLg,
            child: Image.asset(
              kBrandLogoAsset,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'الأكثر نقاطاً لليوم',
            key: Key('dayTopThree.title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.s22,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            dayTopThreeDateLabel(top.day),
            key: const Key('dayTopThree.date'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: AppFontSize.s13),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _navyRaised,
              borderRadius: AppRadius.brLg,
              border: Border.all(color: _gold.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: <Widget>[
                for (var i = 0; i < top.entries.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(color: _gold.withValues(alpha: 0.18), height: 17),
                  _Row(entry: top.entries[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'تطبيق توقعات النخبة | شاركنا الآن!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.s14,
            ),
          ),
        ],
      ),
    );
  }
}

/// One player: his place as a medal, his name and his points.
class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final DayTopEntry entry;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink) = switch (entry.rank) {
      1 => (AppColors.gold, AppColors.onGold),
      2 => (AppColors.silver, AppColors.onSilver),
      _ => (AppColors.bronze, AppColors.onBronze),
    };
    return Row(
      key: Key('dayTopThree.player.${entry.participantId}'),
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Text(
            '${entry.rank}',
            style: TextStyle(
              color: ink,
              fontWeight: FontWeight.w900,
              fontSize: AppFontSize.s18,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            entry.playerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _white,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.s16,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Bounded and scaled down, so large text leaves the name its room.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 104),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              pointsText(entry.points),
              key: Key('dayTopThree.points.${entry.participantId}'),
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
                fontSize: AppFontSize.s16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
