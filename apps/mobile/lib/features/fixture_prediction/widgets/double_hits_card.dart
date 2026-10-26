/// The doubles that paid (owner's request 2026-10-24): every player who
/// made a started match his double of the day and earned points from it,
/// by the server's grade, the same ⚡🔥 the board marks.
///
/// Admins only: the predictions board names each match's doubles above the
/// table, and the line opens a card to share, with the players' names and
/// points or only their count. The card is drawn on screen, captured
/// exactly as seen and handed to the system share sheet (`share_plus`),
/// with the admin's invitation link in the text, like the hero card
/// (`day_hero_card.dart`).
///
/// Nothing is graded here: the points are the server's.
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
import '../../../core/ui/team_logo.dart';
import '../../auth/sign_in_screen.dart' show kBrandLogoAsset;
import '../../competition/team_identity.dart';
import 'day_hero_card.dart' show pointsText;

// A picture that leaves the app keeps the brand's dark colours whatever
// theme the admin runs, read from AppColors so it cannot drift.
const Color _navy = AppColors.background;
const Color _navyRaised = AppColors.surface;
const Color _gold = AppColors.gold;
const Color _white = AppColors.textPrimary;
const Color _muted = AppColors.textMuted;

/// The most names the card lists; the rest are counted.
const int doubleHitsMaxNames = 15;

/// One player whose double paid.
final class DoubleHit {
  /// Creates the line for [playerName], who earned [points].
  const DoubleHit({
    required this.participantId,
    required this.playerName,
    required this.points,
  });

  /// The player's participant id.
  final String participantId;

  /// The player's display name.
  final String playerName;

  /// The points the server gave the double.
  final int points;
}

/// The doubles of one match that paid.
final class DoubleHits {
  /// Creates the facts for one match's [hits].
  const DoubleHits({
    required this.fixtureId,
    required this.home,
    required this.away,
    required this.hits,
    this.leagueName,
  });

  /// The match.
  final String fixtureId;

  /// The home side, resolved for its name and crest.
  final ResolvedTeamIdentity home;

  /// The away side, resolved for its name and crest.
  final ResolvedTeamIdentity away;

  /// The players, most points first, then by name; never empty.
  final List<DoubleHit> hits;

  /// The match's league, when known.
  final String? leagueName;

  /// The points every player earned, or null when they differ.
  int? get samePoints {
    final int first = hits.first.points;
    return hits.every((h) => h.points == first) ? first : null;
  }
}

/// The predictions of one match that were doubles and earned points, by
/// the server's [scores], most points first, then by name; [unnamed] for a
/// player without a name.
List<DoubleHit> doubleHitsOf({
  required Iterable<FixturePredictionDto> predictions,
  required Map<String, ParticipantFixtureScoreDto> scores,
  required String unnamed,
}) {
  final List<DoubleHit> hits = <DoubleHit>[
    for (final FixturePredictionDto p in predictions)
      if (p.isDouble && (scores[p.participantId]?.points ?? 0) > 0)
        DoubleHit(
          participantId: p.participantId,
          playerName: p.displayName.isEmpty ? unnamed : p.displayName,
          points: scores[p.participantId]!.points,
        ),
  ];
  hits.sort((a, b) {
    final int byPoints = b.points.compareTo(a.points);
    return byPoints != 0 ? byPoints : a.playerName.compareTo(b.playerName);
  });
  return hits;
}

/// [count] players in Arabic: لاعب واحد، لاعبان، 3 لاعبين، 11 لاعباً.
String playersText(int count) => switch (count) {
  1 => 'لاعب واحد',
  2 => 'لاعبان',
  >= 3 && <= 10 => '$count لاعبين',
  _ => '$count لاعباً',
};

/// The card's sentence: who doubled the match and what it paid.
String doubleHitsSentence(DoubleHits doubles) {
  final int count = doubles.hits.length;
  final String match =
      '${doubles.home.displayName} × ${doubles.away.displayName}';
  final int? same = doubles.samePoints;
  final String paid = count == 1
      ? 'فحصل على ${pointsText(doubles.hits.first.points)}'
      : same == null
      ? 'فحصلوا على نقاط المضاعفة'
      : 'فحصلوا على نقاط المضاعفة، كل لاعب ${pointsText(same)}';
  return 'اختار ${playersText(count)} مباراة $match مضاعفة، $paid';
}

/// The share text: the sentence, the names when [showNames], and the
/// site's link.
String doubleHitsShareText(DoubleHits doubles, {required bool showNames}) {
  final StringBuffer text = StringBuffer(doubleHitsSentence(doubles));
  if (showNames) {
    for (var i = 0; i < doubles.hits.length; i++) {
      final DoubleHit hit = doubles.hits[i];
      text.write('\n${i + 1}. ${hit.playerName} ${hit.points}');
    }
  }
  text.write('\nشاركنا في نُخبة: ${appSiteLink()}');
  return text.toString();
}

/// Opens the card for [doubles] with its share and close actions.
Future<void> showDoubleHitsCard(BuildContext context, DoubleHits doubles) =>
    showDialog<void>(
      context: context,
      builder: (_) => DoubleHitsShareDialog(doubles: doubles),
    );

/// An admin's line above the board: how many players' doubles of a match
/// paid, and a way to the card.
class DoubleHitsBanner extends StatelessWidget {
  /// Creates the line for [doubles].
  const DoubleHitsBanner({required this.doubles, super.key});

  /// The match's doubles.
  final DoubleHits doubles;

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
          key: Key('fixturePredictions.doubles.${doubles.fixtureId}'),
          borderRadius: AppRadius.brButton,
          onTap: () => unawaited(showDoubleHitsCard(context, doubles)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.bolt_rounded,
                  size: AppSizes.iconSm,
                  color: tokens.goldAccent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'مضاعفة ناجحة: ${playersText(doubles.hits.length)} · '
                    '${doubles.home.displayName} × ${doubles.away.displayName}',
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

/// The preview of the card, with the names switch and the share and close
/// actions.
class DoubleHitsShareDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for [doubles].
  const DoubleHitsShareDialog({required this.doubles, super.key});

  /// What the card shows.
  final DoubleHits doubles;

  @override
  ConsumerState<DoubleHitsShareDialog> createState() =>
      _DoubleHitsShareDialogState();
}

class _DoubleHitsShareDialogState extends ConsumerState<DoubleHitsShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _showNames = true;
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
              child: DoubleHitsCard(
                doubles: widget.doubles,
                showNames: _showNames,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              key: const Key('doubleHits.names'),
              contentPadding: EdgeInsets.zero,
              value: _showNames,
              onChanged: (value) => setState(() => _showNames = value),
              title: const Text('إظهار أسماء اللاعبين'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('doubleHits.share'),
                    onPressed: _sharing ? null : () => unawaited(_share()),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('مشاركة البطاقة'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  key: const Key('doubleHits.close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
            if (_shareFailed) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                sharePictureFailedText,
                key: const Key('doubleHits.failed'),
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
        text: doubleHitsShareText(widget.doubles, showNames: _showNames),
        fileName: 'nukhba-doubles.png',
      );
      if (mounted && !shared) setState(() => _shareFailed = true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// The picture itself: the match, then the players and their points, or
/// only how many they were when [showNames] is off.
class DoubleHitsCard extends StatelessWidget {
  /// Creates the card for [doubles].
  const DoubleHitsCard({
    required this.doubles,
    required this.showNames,
    super.key,
  });

  /// What the card shows.
  final DoubleHits doubles;

  /// The players are named.
  final bool showNames;

  @override
  Widget build(BuildContext context) {
    final String? league = doubles.leagueName;
    final List<DoubleHit> listed = doubles.hits
        .take(doubleHitsMaxNames)
        .toList();
    final int more = doubles.hits.length - listed.length;
    final int? same = doubles.samePoints;
    return Container(
      key: const Key('doubleHits.card'),
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
            'بطاقة المضاعفة الناجحة',
            key: Key('doubleHits.title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.s22,
            ),
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
                    _Side(team: doubles.home),
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
                    _Side(team: doubles.away),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.bolt_rounded, color: _gold, size: 22),
                    SizedBox(width: AppSpacing.xs),
                    Text(
                      'مضاعفة',
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w800,
                        fontSize: AppFontSize.s16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Divider(color: _gold.withValues(alpha: 0.25), height: 1),
                const SizedBox(height: AppSpacing.md),
                if (showNames) ...<Widget>[
                  for (var i = 0; i < listed.length; i++)
                    Padding(
                      key: Key('doubleHits.player.${listed[i].participantId}'),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${i + 1}.',
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w800,
                                fontSize: AppFontSize.s14,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              listed[i].playerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _white,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.s14,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${listed[i].points}',
                            style: const TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.w900,
                              fontSize: AppFontSize.s16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (more > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'و${playersText(more)} غيرهم',
                        key: const Key('doubleHits.more'),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: AppFontSize.s13,
                        ),
                      ),
                    ),
                ] else ...<Widget>[
                  Text(
                    '${doubles.hits.length}',
                    key: const Key('doubleHits.count'),
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w900,
                      fontSize: AppFontSize.s26,
                    ),
                  ),
                  Text(
                    doubles.hits.length == 1
                        ? 'لاعب ضاعف هذه المباراة'
                        : 'لاعبين ضاعفوا هذه المباراة',
                    style: const TextStyle(
                      color: _white,
                      fontSize: AppFontSize.s14,
                    ),
                  ),
                  if (same != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      doubles.hits.length == 1
                          ? 'فحصل على ${pointsText(same)}'
                          : 'كل لاعب ${pointsText(same)}',
                      key: const Key('doubleHits.each'),
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.s14,
                      ),
                    ),
                  ],
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
