/// Share a hit (decided 2026-09-28): a finished prediction that earned points
/// can be shared as a picture card -- the Nukhba logo, the match, the call
/// and the final score, the points, the viewer's place in the month -- with
/// the viewer's invitation link in the text, so a share can bring a friend
/// in through the invitation system.
///
/// Every number on the card is the server's: the points from the scores read
/// the card above already made, the place from the month's board. The card
/// is drawn on screen first, then captured exactly as seen and handed to the
/// system share sheet (`share_plus`).
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_typography.dart';
import '../../l10n/app_localizations.dart';
import '../auth/sign_in_screen.dart' show kBrandLogoAsset;
import '../competition/team_registry.dart';
import '../gamification/invite_friends_screen.dart';
import '../leaderboards/leaderboards_providers.dart';

// The card is a picture that leaves the app, so it keeps the brand's own
// colours whatever theme the viewer runs.
const Color _navy = Color(0xFF071426);
const Color _navyRaised = Color(0xFF0E2140);
const Color _blue = Color(0xFF008BFF);
const Color _gold = Color(0xFFF5C451);
const Color _white = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9FB0C8);

/// The facts one hit card shows.
final class ExactHit {
  /// Creates the facts for [prediction].
  const ExactHit({
    required this.prediction,
    required this.fixture,
    required this.resultHome,
    required this.resultAway,
    required this.points,
  });

  /// The viewer's own prediction.
  final FixturePredictionDto prediction;

  /// The match, when the current-month feed knows it.
  final SeasonFixtureCardDto? fixture;

  /// The recorded final score.
  final int? resultHome;

  /// The recorded final score.
  final int? resultAway;

  /// The points scoring gave (the server's).
  final int points;
}

/// "Share your hit" under a finished prediction that earned points.
class ShareHitButton extends StatelessWidget {
  /// Creates the button for [hit].
  const ShareHitButton({required this.hit, super.key});

  /// What the card will show.
  final ExactHit hit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return TextButton.icon(
      onPressed: () => unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => ExactHitShareDialog(hit: hit),
        ),
      ),
      icon: const Icon(Icons.ios_share_rounded),
      label: Text(l10n.historyShareHit),
    );
  }
}

/// The preview of the card, with the share and close actions.
class ExactHitShareDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for [hit].
  const ExactHitShareDialog({required this.hit, super.key});

  /// What the card shows.
  final ExactHit hit;

  @override
  ConsumerState<ExactHitShareDialog> createState() =>
      _ExactHitShareDialogState();
}

class _ExactHitShareDialogState extends ConsumerState<ExactHitShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ExactHit hit = widget.hit;
    final String? seasonId = hit.prediction.seasonId;

    // The viewer's place in the month: decoration, so a failed or slow read
    // simply leaves the line out.
    int? rank;
    if (seasonId != null) {
      final List<FixtureLeaderboardEntryDto> entries =
          ref.watch(fixtureLeaderboardProvider(seasonId)).value?.entries ??
          const <FixtureLeaderboardEntryDto>[];
      for (final FixtureLeaderboardEntryDto entry in entries) {
        if (entry.participantId == hit.prediction.participantId) {
          rank = entry.rank;
          break;
        }
      }
    }
    final String? code = ref.watch(myReferralProvider).value?.code;

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RepaintBoundary(
              key: _cardKey,
              child: ExactHitCard(hit: hit, rank: rank),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('shareHit.share'),
                    onPressed: _sharing ? null : () => unawaited(_share(code)),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(l10n.shareHitShareButton),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  key: const Key('shareHit.close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.shareHitCloseButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(String? code) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ExactHit hit = widget.hit;
    setState(() => _sharing = true);
    try {
      final RenderObject? object = _cardKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;
      final ui.Image image = await object.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      final String message = l10n.shareHitMessage(
        teamDisplayName(hit.fixture?.homeTeam),
        '${hit.prediction.homeGoals}-${hit.prediction.awayGoals}',
        teamDisplayName(hit.fixture?.awayTeam),
      );
      final String text = code == null || code.isEmpty
          ? message
          : '$message\n${l10n.shareHitJoin(inviteLinkFor(code))}';
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: <XFile>[
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'nukhba-hit.png',
            ),
          ],
          fileNameOverrides: const <String>['nukhba-hit.png'],
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

/// The picture itself.
class ExactHitCard extends StatelessWidget {
  /// Creates the card for [hit]; [rank] is the viewer's place in the month.
  const ExactHitCard({required this.hit, this.rank, super.key});

  /// What the card shows.
  final ExactHit hit;

  /// The viewer's place in the month, when known.
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool doubled = hit.prediction.isDouble;
    final String home = teamDisplayName(hit.fixture?.homeTeam);
    final String away = teamDisplayName(hit.fixture?.awayTeam);
    final String? league = hit.fixture?.leagueName;
    const TextStyle white = TextStyle(color: _white);
    return Container(
      key: const Key('shareHit.card'),
      width: 320,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: _navy,
        borderRadius: AppRadius.brCardLarge,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: AppRadius.brMd,
                child: Image.asset(
                  kBrandLogoAsset,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.appTitle,
                      style: white.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: AppFontSize.s18,
                      ),
                    ),
                    Text(
                      l10n.tagline,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: AppFontSize.s11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            doubled ? l10n.shareHitDoubleTitle : l10n.shareHitTitle,
            key: const Key('shareHit.title'),
            style: TextStyle(
              color: doubled ? _gold : _white,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.s18,
            ),
          ),
          if (league != null && league.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              league,
              style: const TextStyle(color: _muted, fontSize: AppFontSize.s12),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.fixtureVsTitle(home, away),
            textAlign: TextAlign.center,
            style: white.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.s15,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _ScoreBox(
                  label: l10n.shareHitMyCall,
                  home: hit.prediction.homeGoals,
                  away: hit.prediction.awayGoals,
                  accent: _blue,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ScoreBox(
                  label: l10n.shareHitFinal,
                  home: hit.resultHome,
                  away: hit.resultAway,
                  accent: _muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${doubled ? '⚡🔥' : '✅'} ${l10n.shareHitPoints(hit.points)}',
            key: const Key('shareHit.points'),
            style: const TextStyle(
              color: _gold,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.s18,
            ),
          ),
          if (rank != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.shareHitRank(rank!),
              key: const Key('shareHit.rank'),
              style: white.copyWith(fontSize: AppFontSize.s13),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled score; home goals on the reading side, as everywhere else.
class _ScoreBox extends StatelessWidget {
  const _ScoreBox({
    required this.label,
    required this.home,
    required this.away,
    required this.accent,
  });

  final String label;
  final int? home;
  final int? away;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const TextStyle digits = TextStyle(
      color: _white,
      fontWeight: FontWeight.w800,
      fontSize: AppFontSize.s18,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: _navyRaised,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: accent),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(color: _muted, fontSize: AppFontSize.s11),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('${home ?? '-'}', style: digits),
              const Text(' - ', style: TextStyle(color: _muted)),
              Text('${away ?? '-'}', style: digits),
            ],
          ),
        ],
      ),
    );
  }
}
