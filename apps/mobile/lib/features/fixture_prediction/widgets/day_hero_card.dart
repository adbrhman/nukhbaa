/// The hero of the day (decided 2026-10-07): the one player who, alone
/// among everyone, called a finished match's exact score. Each match of the
/// day can have one; none when two or more called it, or nobody did.
///
/// Only admins see it: the predictions board names each hero above the
/// table and marks the cell, and tapping that prediction offers the card.
/// The card is drawn on screen, captured exactly as seen and handed to the
/// system share sheet (`share_plus`), with the admin's invitation link in
/// the text, like the hit card (`exact_hit_share.dart`).
///
/// Nothing is graded here: the exact call is the server's grade
/// (`exact_scoreline`) from the same scores the board shows.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/team_logo.dart';
import '../../auth/sign_in_screen.dart' show kBrandLogoAsset;
import '../../competition/team_identity.dart';
import '../../gamification/invite_friends_screen.dart';

// A picture that leaves the app keeps the brand's dark colours whatever
// theme the admin runs, read from AppColors so it cannot drift.
const Color _navy = AppColors.background;
const Color _navyRaised = AppColors.surface;
const Color _gold = AppColors.gold;
const Color _white = AppColors.textPrimary;
const Color _muted = AppColors.textMuted;

/// The server's grade for an exact call.
const String exactScorelineGrade = 'exact_scoreline';

/// The one participant whose prediction [scores] grade as an exact call,
/// or null when none or several do.
String? soloExactParticipant(Iterable<ParticipantFixtureScoreDto> scores) {
  String? only;
  for (final ParticipantFixtureScoreDto score in scores) {
    if (score.grade != exactScorelineGrade) continue;
    if (only != null) return null;
    only = score.participantId;
  }
  return only;
}

/// The facts one hero card shows.
final class DayHero {
  /// Creates the facts for [playerName]'s call of one match.
  const DayHero({
    required this.fixtureId,
    required this.participantId,
    required this.playerName,
    required this.home,
    required this.away,
    required this.homeGoals,
    required this.awayGoals,
    this.leagueName,
  });

  /// The match.
  final String fixtureId;

  /// The hero's participant id.
  final String participantId;

  /// The hero's display name.
  final String playerName;

  /// The home side, resolved for its name and crest.
  final ResolvedTeamIdentity home;

  /// The away side, resolved for its name and crest.
  final ResolvedTeamIdentity away;

  /// The exact call, which is also the final score.
  final int homeGoals;

  /// The exact call, which is also the final score.
  final int awayGoals;

  /// The match's league, when known.
  final String? leagueName;
}

/// Opens the card for [hero] with its share and close actions.
Future<void> showDayHeroCard(BuildContext context, DayHero hero) =>
    showDialog<void>(
      context: context,
      builder: (_) => DayHeroShareDialog(hero: hero),
    );

/// An admin's line above the board: who is the hero of a match, and a way
/// to the card.
class DayHeroBanner extends StatelessWidget {
  /// Creates the line for [hero].
  const DayHeroBanner({required this.hero, super.key});

  /// The hero named.
  final DayHero hero;

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
          key: Key('fixturePredictions.hero.${hero.fixtureId}'),
          borderRadius: AppRadius.brButton,
          onTap: () => unawaited(showDayHeroCard(context, hero)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.emoji_events_rounded,
                  size: AppSizes.iconSm,
                  color: tokens.goldAccent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'بطل اليوم: ${hero.playerName} · '
                    '${hero.home.displayName} × ${hero.away.displayName}',
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
class DayHeroShareDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for [hero].
  const DayHeroShareDialog({required this.hero, super.key});

  /// What the card shows.
  final DayHero hero;

  @override
  ConsumerState<DayHeroShareDialog> createState() => _DayHeroShareDialogState();
}

class _DayHeroShareDialogState extends ConsumerState<DayHeroShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final String? code = ref.watch(myReferralProvider).value?.code;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RepaintBoundary(
              key: _cardKey,
              child: DayHeroCard(hero: widget.hero),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('dayHero.share'),
                    onPressed: _sharing ? null : () => unawaited(_share(code)),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('مشاركة البطاقة'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  key: const Key('dayHero.close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(String? code) async {
    final DayHero hero = widget.hero;
    setState(() => _sharing = true);
    try {
      final RenderObject? object = _cardKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;
      final ui.Image image = await object.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      final String message =
          'بطل النخبة اليوم: ${hero.playerName}، وحده توقّع '
          '${hero.home.displayName} ${hero.homeGoals}-${hero.awayGoals} '
          '${hero.away.displayName} تماماً.';
      final String text = code == null || code.isEmpty
          ? message
          : '$message\nشاركنا في نُخبة: ${inviteLinkFor(code)}';
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: <XFile>[
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'nukhba-hero.png',
            ),
          ],
          fileNameOverrides: const <String>['nukhba-hero.png'],
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// The picture itself.
class DayHeroCard extends StatelessWidget {
  /// Creates the card for [hero].
  const DayHeroCard({required this.hero, super.key});

  /// What the card shows.
  final DayHero hero;

  @override
  Widget build(BuildContext context) {
    const TextStyle white = TextStyle(color: _white);
    final String? league = hero.leagueName;
    return Container(
      key: const Key('dayHero.card'),
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
            'بطاقة بطل النخبة لليوم',
            key: Key('dayHero.title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.s22,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _navyRaised,
              borderRadius: AppRadius.brLg,
              border: Border.all(color: _gold.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: _muted,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        hero.playerName,
                        key: const Key('dayHero.name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: white.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.s20,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      children: <Widget>[
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            gradient: AppColors.goldGradient,
                            borderRadius: AppRadius.brSm,
                          ),
                          child: const Text(
                            '1',
                            style: TextStyle(
                              color: AppColors.onGold,
                              fontWeight: FontWeight.w900,
                              fontSize: AppFontSize.s22,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'منفرد',
                          key: Key('dayHero.solo'),
                          style: TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.s13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Divider(color: _gold.withValues(alpha: 0.25), height: 1),
                const SizedBox(height: AppSpacing.md),
                if (league != null && league.isNotEmpty) ...<Widget>[
                  Text(
                    league,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: AppFontSize.s12,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                // Home on the reading side, as on the board.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _Side(team: hero.home),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text(
                        'ضد',
                        style: TextStyle(
                          color: _gold,
                          fontSize: AppFontSize.s13,
                        ),
                      ),
                    ),
                    _Side(team: hero.away),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  key: const Key('dayHero.score'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text('${hero.homeGoals}', style: _scoreStyle),
                    const Text(' - ', style: _scoreStyle),
                    Text('${hero.awayGoals}', style: _scoreStyle),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'توقع صحيح تماماً',
                  style: white.copyWith(fontSize: AppFontSize.s14),
                ),
                const Text(
                  '(نتيجة مطابقة)',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.s13,
                  ),
                ),
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

const TextStyle _scoreStyle = TextStyle(
  color: _gold,
  fontWeight: FontWeight.w900,
  fontSize: AppFontSize.s26,
);

/// One side of the match: its crest and its name.
class _Side extends StatelessWidget {
  const _Side({required this.team});

  final ResolvedTeamIdentity team;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TeamLogo(
            displayName: team.displayName,
            assetPath: team.assetPath,
            crestUrl: team.crestUrl,
            brandColor: team.brandColor,
            size: 24,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              team.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _white,
                fontWeight: FontWeight.w700,
                fontSize: AppFontSize.s14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
