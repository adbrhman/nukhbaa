/// The sheet that accepts a duel challenge with the caller's own
/// prediction (`POST /duels/challenges/{id}/accept`).
///
/// The scoreline starts from the caller's saved prediction for the fixture
/// when there is one, and keeps its double, so accepting never quietly
/// removes the day's double. The server saves the prediction first, then
/// creates the duel, and never changes the double (audit M-12).
///
/// Nothing can be sent before the saved predictions have loaded: a sheet
/// opened offline or straight from a code used to send 0-0 over the saved
/// score. A failed load says so and offers a retry.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/analytics/screen_views.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/format/timestamps.dart';
import '../competition/team_registry.dart';
import '../history/prediction_history_providers.dart';
import '../history/prediction_lookup_providers.dart';
import 'duel_texts.dart';
import 'duels_providers.dart';

/// Opens the sheet for [challenge]; completes with true once accepted.
Future<bool?> showAcceptDuelSheet({
  required BuildContext context,
  required DuelChallengeDto challenge,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AcceptDuelSheet(challenge: challenge),
  );
}

/// The sheet body; public so a widget test can pump it directly.
class AcceptDuelSheet extends ConsumerStatefulWidget implements NamedScreen {
  @override
  String get screenName => ScreenNames.duelAccept;

  /// Creates the sheet for [challenge].
  const AcceptDuelSheet({required this.challenge, super.key});

  /// The challenge being accepted.
  final DuelChallengeDto challenge;

  @override
  ConsumerState<AcceptDuelSheet> createState() => _AcceptDuelSheetState();
}

class _AcceptDuelSheetState extends ConsumerState<AcceptDuelSheet> {
  /// The player's own choice; null until they touch a stepper, so the
  /// saved prediction (which may arrive after the sheet opens) shows first.
  int? _home;
  int? _away;
  bool _busy = false;
  String? _error;

  /// Retries the read the sheet waits for.
  void _retryLoad() => ref.invalidate(myFixturePredictionsProvider);

  Future<void> _accept({
    required int home,
    required int away,
    required bool isDouble,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<DuelDto> result = await ref
        .read(duelsApiProvider)
        .acceptChallenge(
          widget.challenge.id,
          homeGoals: home,
          awayGoals: away,
          isDouble: isDouble,
        );
    if (!mounted) return;
    switch (result) {
      case Ok<DuelDto>():
        ref
          ..invalidate(myDuelsProvider)
          ..invalidate(myFixturePredictionsProvider);
        Navigator.of(context).pop(true);
      case Err<DuelDto>(:final error):
        setState(() {
          _busy = false;
          _error = duelErrorMessage(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final DuelChallengeDto challenge = widget.challenge;
    final AsyncValue<Map<String, FixturePredictionDto>> mine = ref.watch(
      myFixturePredictionsByFixtureProvider,
    );
    // Until the saved predictions arrive the sheet cannot know the score it
    // would overwrite, so nothing can be changed or sent.
    final bool ready = mine.hasValue;
    final bool loadFailed = !ready && mine.hasError;
    final bool enabled = ready && !_busy;
    final FixturePredictionDto? saved = mine.value?[challenge.fixtureId];
    final int home = _home ?? saved?.homeGoals ?? 0;
    final int away = _away ?? saved?.awayGoals ?? 0;
    // The double is the saved prediction's, never changed here.
    final bool isDouble = saved?.isDouble ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          key: const Key('acceptDuel.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${challenge.challengerName} يتحداك',
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              duelFixtureTitle(challenge.homeTeam, challenge.awayTeam),
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(color: tokens.textSecondary),
            ),
            Text(
              formatDayAndTime(context, challenge.kickoffAt),
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'توقعك',
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _Stepper(
                  keyPrefix: 'acceptDuel.home',
                  label: teamDisplayName(challenge.homeTeam),
                  value: home,
                  enabled: enabled,
                  onChanged: (int v) => setState(() => _home = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(
                    '-',
                    style: text.headlineSmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                _Stepper(
                  keyPrefix: 'acceptDuel.away',
                  label: teamDisplayName(challenge.awayTeam),
                  value: away,
                  enabled: enabled,
                  onChanged: (int v) => setState(() => _away = v),
                ),
              ],
            ),
            if (ready) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                saved == null
                    ? 'هذه النتيجة تُحفظ توقعَك لهذه المباراة.'
                    : 'تغيير النتيجة هنا يغيّر توقعك المحفوظ لهذه المباراة.',
                key: const Key('acceptDuel.note'),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ],
            if (isDouble) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'توقعك على هذه المباراة مضاعف، ويبقى كذلك.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: tokens.goldAccent),
              ),
            ],
            if (loadFailed) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'تعذّر تحميل توقعك المحفوظ لهذه المباراة.',
                key: const Key('acceptDuel.loadError'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: tokens.errorText),
              ),
              TextButton(
                key: const Key('acceptDuel.retry'),
                onPressed: _retryLoad,
                child: const Text('إعادة المحاولة'),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('acceptDuel.accept'),
              onPressed: enabled
                  ? () => unawaited(
                      _accept(home: home, away: away, isDouble: isDouble),
                    )
                  : null,
              child: Text(
                _busy
                    ? 'جارٍ القبول…'
                    : ready || loadFailed
                    ? 'اقبل التحدي'
                    : 'جارٍ تحميل توقعك…',
              ),
            ),
            if (_error case final String message) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                key: const Key('acceptDuel.error'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: tokens.errorText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: AppRadius.brButton,
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                key: Key('$keyPrefix.decrement'),
                onPressed: enabled && value > 0
                    ? () => onChanged(value - 1)
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '$value',
                  key: Key('$keyPrefix.value'),
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: Key('$keyPrefix.increment'),
                onPressed: enabled && value < 20
                    ? () => onChanged(value + 1)
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
