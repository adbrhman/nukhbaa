/// The sheet behind a cell of the predictions board (migration 0094): one
/// player's prediction, the reactions it received, and -- on someone
/// else's -- the six reactions to give, change, or take back by tapping the
/// chosen one again. The owner hears of the first reaction each player
/// gives, in the inbox. Reactions carry no points.
///
/// Every kind is drawn as an icon with its name: emoji glyphs show as boxes
/// in the app's typeface. Each kind keeps its own colour, from the theme's
/// tokens so both themes keep their contrast; the viewer's own choice is the
/// blue frame and the blue name.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/analytics/screen_views.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/providers.dart';
import '../fixture_prediction_providers.dart';
import '../prediction_reactions_providers.dart';

/// How each reaction kind looks: its icon and its name.
const Map<String, (IconData, String)> predictionReactionLooks =
    <String, (IconData, String)>{
      'like': (Icons.thumb_up_alt_rounded, 'أعجبني'),
      'fire': (Icons.local_fire_department_rounded, 'نار'),
      'clap': (Icons.celebration_rounded, 'تصفيق'),
      'laugh': (Icons.sentiment_very_satisfied_rounded, 'ضحك'),
      'sad': (Icons.sentiment_dissatisfied_rounded, 'حزين'),
      'shock': (Icons.priority_high_rounded, 'مفاجأة'),
    };

/// The colour of each reaction kind, wherever it is drawn.
Color predictionReactionColor(AppTokens tokens, String kind) => switch (kind) {
  'like' => tokens.primaryText,
  'fire' => tokens.bronze,
  'clap' => tokens.successText,
  'laugh' => tokens.goldAccent,
  'sad' => tokens.silver,
  'shock' => tokens.errorText,
  _ => tokens.textSecondary,
};

/// The kind [tally] received most, the first in [predictionReactionKinds]
/// order on a tie; null when it received none.
String? leadingReactionKind(PredictionReactionTallyDto tally) {
  String? best;
  int most = 0;
  for (final String kind in predictionReactionKinds) {
    final int count = tally.counts[kind] ?? 0;
    if (count > most) {
      most = count;
      best = kind;
    }
  }
  return best;
}

/// Opens the sheet for one cell of the board.
Future<void> showPredictionReactionSheet({
  required BuildContext context,
  required String seasonId,
  required String fixtureId,
  required String participantId,
  required String playerName,
  required String homeName,
  required String awayName,
  required int homeGoals,
  required int awayGoals,
  required bool isMine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PredictionReactionSheet(
      seasonId: seasonId,
      fixtureId: fixtureId,
      participantId: participantId,
      playerName: playerName,
      homeName: homeName,
      awayName: awayName,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isMine: isMine,
    ),
  );
}

/// The sheet body; public so a widget test can pump it directly.
class PredictionReactionSheet extends ConsumerStatefulWidget
    implements NamedScreen {
  @override
  String get screenName => ScreenNames.predictionReactions;

  /// Creates the sheet for [participantId]'s prediction of [fixtureId].
  const PredictionReactionSheet({
    required this.seasonId,
    required this.fixtureId,
    required this.participantId,
    required this.playerName,
    required this.homeName,
    required this.awayName,
    required this.homeGoals,
    required this.awayGoals,
    required this.isMine,
    super.key,
  });

  final String seasonId;
  final String fixtureId;
  final String participantId;
  final String playerName;
  final String homeName;
  final String awayName;
  final int homeGoals;
  final int awayGoals;

  /// The viewer's own prediction: its reactions are shown, none is given.
  final bool isMine;

  @override
  ConsumerState<PredictionReactionSheet> createState() =>
      _PredictionReactionSheetState();
}

class _PredictionReactionSheetState
    extends ConsumerState<PredictionReactionSheet> {
  bool _busy = false;
  String? _error;

  FixturePredictionDistributionKey get _key =>
      (seasonId: widget.seasonId, fixtureId: widget.fixtureId);

  Future<void> _choose(String kind, String? mine) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(predictionApiProvider);
    final Result<bool> result = kind == mine
        ? await api.removePredictionReaction(
            seasonId: widget.seasonId,
            fixtureId: widget.fixtureId,
            participantId: widget.participantId,
          )
        : await api.reactToPrediction(
            seasonId: widget.seasonId,
            fixtureId: widget.fixtureId,
            participantId: widget.participantId,
            kind: kind,
          );
    if (!mounted) return;
    if (result is Ok<bool>) {
      ref.invalidate(predictionReactionsProvider(_key));
    }
    setState(() {
      _busy = false;
      _error = result is Ok<bool> ? null : 'تعذّر حفظ تفاعلك. حاول مرة أخرى.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final PredictionReactionTallyDto? tally = ref
        .watch(predictionReactionsProvider(_key))
        .value
        ?.of(widget.participantId);
    final String? mine = tally?.mine;
    final TextStyle? names = text.bodyMedium?.copyWith(
      color: tokens.textSecondary,
    );
    final TextStyle? goals = text.titleMedium?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w800,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          key: const Key('reactionSheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.isMine ? 'توقعك' : 'توقع ${widget.playerName}',
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // A Row follows the reading direction: home on the reading
            // side, as on the board's header and cells.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: Text(
                    widget.homeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: names,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('${widget.homeGoals}', style: goals),
                Text(' - ', style: names),
                Text('${widget.awayGoals}', style: goals),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    widget.awayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: names,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              widget.isMine
                  ? 'تفاعل اللاعبين مع توقعك'
                  : mine == null
                  ? 'تفاعل مع توقعه. يصله إشعار باسمك.'
                  : 'اضغط تفاعلك مرة أخرى لإزالته.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                for (final String kind in predictionReactionKinds)
                  _ReactionButton(
                    kind: kind,
                    count: tally?.counts[kind] ?? 0,
                    selected: kind == mine,
                    onTap: widget.isMine || _busy
                        ? null
                        : () => unawaited(_choose(kind, mine)),
                  ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                key: const Key('reactionSheet.error'),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: tokens.errorText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.kind,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String kind;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final (IconData icon, String label) = predictionReactionLooks[kind]!;
    final Color color = selected ? tokens.primaryText : tokens.textSecondary;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
        child: Semantics(
          button: true,
          selected: selected,
          label: count > 0 ? '$label $count' : label,
          excludeSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: Key('reactionSheet.kind.$kind'),
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: selected
                      ? tokens.primary.withValues(alpha: 0.16)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? tokens.primary : tokens.border,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: AppSizes.iconLg,
                      color: predictionReactionColor(tokens, kind),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: color,
                          fontSize: AppFontSize.s12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      count > 0 ? '$count' : ' ',
                      key: Key('reactionSheet.count.$kind'),
                      style: TextStyle(
                        color: color,
                        fontSize: AppFontSize.s12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
