/// Everyone's predictions for one started fixture (decided 2026-09-28).
///
/// Opened from the match card's slot that held "double your points" before
/// kickoff. The server reveals the list only once the fixture has kicked off
/// (`GET /seasons/{id}/fixtures/{fixtureId}/predictions`), so this sheet
/// never decides visibility itself: a refusal from the server is shown as
/// its message, never worked around. The points beside each name come from
/// the same server scores the card already reads; nothing is computed here.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/error/error_presenter.dart';
import '../../../l10n/app_localizations.dart';
import '../../history/fixture_scores_providers.dart';
import '../fixture_prediction_providers.dart';

/// Opens the sheet listing every prediction for [fixtureId].
///
/// [myParticipantId] marks the caller's own row when they predicted.
Future<void> showFixturePredictionsSheet({
  required BuildContext context,
  required String seasonId,
  required String fixtureId,
  required String homeTeam,
  required String awayTeam,
  String? myParticipantId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FixturePredictionsSheet(
      seasonId: seasonId,
      fixtureId: fixtureId,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      myParticipantId: myParticipantId,
    ),
  );
}

/// The list itself: a name search and one row per prediction.
class FixturePredictionsSheet extends ConsumerStatefulWidget {
  /// Creates the sheet for [fixtureId] in [seasonId].
  const FixturePredictionsSheet({
    required this.seasonId,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    this.myParticipantId,
    super.key,
  });

  /// The season the fixture belongs to.
  final String seasonId;

  /// The started fixture.
  final String fixtureId;

  /// Home team name, already resolved for display.
  final String homeTeam;

  /// Away team name, already resolved for display.
  final String awayTeam;

  /// The caller's own participant id, when they predicted this fixture.
  final String? myParticipantId;

  @override
  ConsumerState<FixturePredictionsSheet> createState() =>
      _FixturePredictionsSheetState();
}

class _FixturePredictionsSheetState
    extends ConsumerState<FixturePredictionsSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final FixturePredictionDistributionKey key = (
      seasonId: widget.seasonId,
      fixtureId: widget.fixtureId,
    );
    final AsyncValue<List<FixturePredictionDto>> reveal = ref.watch(
      fixturePredictionsRevealProvider(key),
    );
    final Map<String, ParticipantFixtureScoreDto> scores = {
      for (final ParticipantFixtureScoreDto s
          in ref
                  .watch(
                    fixtureScoresProvider(widget.seasonId, widget.fixtureId),
                  )
                  .value
                  ?.scores ??
              const <ParticipantFixtureScoreDto>[])
        s.participantId: s,
    };

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Container(
            key: Key('fixturePredictions.sheet.${widget.fixtureId}'),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              border: Border.all(color: tokens.border),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: tokens.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  l10n.fixturePredictionsTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.s16,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.fixtureVsTitle(widget.homeTeam, widget.awayTeam),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: AppFontSize.s13,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('fixturePredictions.search'),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.fixturePredictionsSearchHint,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: AppSizes.iconMd,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadius.brButton,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Flexible(
                  child: switch (reveal) {
                    AsyncData<List<FixturePredictionDto>>(:final value) =>
                      _list(context, value, scores),
                    AsyncError<List<FixturePredictionDto>>(:final error) =>
                      _message(
                        context,
                        error is AppError
                            ? ErrorPresenter.message(error)
                            : l10n.fixturePredictionsLoadFailed,
                        key: const Key('fixturePredictions.error'),
                      ),
                    _ => const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<FixturePredictionDto> all,
    Map<String, ParticipantFixtureScoreDto> scores,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (all.isEmpty) {
      return _message(
        context,
        l10n.fixturePredictionsEmpty,
        key: const Key('fixturePredictions.empty'),
      );
    }
    final List<FixturePredictionDto> rows =
        all
            .where(
              (p) =>
                  _query.isEmpty ||
                  p.displayName.toLowerCase().contains(_query),
            )
            .toList()
          ..sort((a, b) {
            // Mine first, then the most points, then by name.
            final bool aMine = a.participantId == widget.myParticipantId;
            final bool bMine = b.participantId == widget.myParticipantId;
            if (aMine != bMine) return aMine ? -1 : 1;
            final int byPoints = (scores[b.participantId]?.points ?? -1)
                .compareTo(scores[a.participantId]?.points ?? -1);
            if (byPoints != 0) return byPoints;
            return a.displayName.compareTo(b.displayName);
          });
    if (rows.isEmpty) {
      return _message(
        context,
        l10n.fixturePredictionsNoMatch,
        key: const Key('fixturePredictions.noMatch'),
      );
    }
    return ListView.separated(
      key: const Key('fixturePredictions.list'),
      shrinkWrap: true,
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final FixturePredictionDto p = rows[index];
        return _PredictionRow(
          prediction: p,
          score: scores[p.participantId],
          isMine: p.participantId == widget.myParticipantId,
        );
      },
    );
  }

  Widget _message(BuildContext context, String text, {required Key key}) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        text,
        key: key,
        textAlign: TextAlign.center,
        style: TextStyle(color: tokens.textSecondary),
      ),
    );
  }
}

/// One player's prediction: name, the predicted score laid out like the card
/// (home side first in reading order), the double mark, and the points once
/// the server has graded the fixture.
class _PredictionRow extends StatelessWidget {
  const _PredictionRow({
    required this.prediction,
    required this.score,
    required this.isMine,
  });

  final FixturePredictionDto prediction;
  final ParticipantFixtureScoreDto? score;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final String name = prediction.displayName.isEmpty
        ? l10n.fixturePredictionsUnnamed
        : prediction.displayName;
    final ParticipantFixtureScoreDto? graded = score;
    return Container(
      key: Key('fixturePredictions.row.${prediction.participantId}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isMine
            ? tokens.primary.withValues(alpha: 0.12)
            : tokens.surfaceElevated,
        borderRadius: AppRadius.brButton,
        border: Border.all(color: isMine ? tokens.primary : tokens.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              isMine ? l10n.fixturePredictionsMine(name) : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
                fontSize: AppFontSize.s14,
              ),
            ),
          ),
          if (prediction.isDouble)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
              child: Icon(
                Icons.bolt_rounded,
                key: Key(
                  'fixturePredictions.double.${prediction.participantId}',
                ),
                size: AppSizes.iconSm,
                color: tokens.gold,
              ),
            ),
          // A Row follows the reading direction, so the home goals sit on
          // the home team's side exactly as on the card.
          Row(
            key: Key('fixturePredictions.score.${prediction.participantId}'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${prediction.homeGoals}',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.s16,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text('-', style: TextStyle(color: tokens.textMuted)),
              ),
              Text(
                '${prediction.awayGoals}',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.s16,
                ),
              ),
            ],
          ),
          if (graded != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
              child: Text(
                l10n.fixturePredictionsPoints(graded.points),
                key: Key(
                  'fixturePredictions.points.${prediction.participantId}',
                ),
                style: TextStyle(
                  color: graded.points > 0 ? tokens.success : tokens.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.s12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
