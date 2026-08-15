/// The unified **Matches** screen — every open round's fixture(s) across
/// every competition in one scrollable feed, each rendered with the exact
/// same dark match card as the single-round prediction screen
/// (`../prediction/match_card.dart`): a color-bled crest header, +/?/−
/// goal steppers, and a Double star toggle (there is no win-probability
/// display to replace — the card never had one).
///
/// Reuses every existing read/write exactly as-is:
///   * `matchesFeedProvider` — the client-side composition of the existing
///     Competition browse reads (see `matches_feed_providers.dart`).
///   * `myPredictionProvider(roundId)` / `predictionControllerProvider(roundId)`
///     — the same read/submit pair the single-round prediction screen uses,
///     one instance per round. Predictions are shown and submitted directly
///     inline (no navigation to a separate screen).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_tokens.dart';

import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import '../prediction/match_card.dart';
import '../prediction/prediction_controller.dart';
import '../prediction/prediction_providers.dart';
import '../prediction/prediction_submission.dart';
import 'matches_feed_providers.dart';

/// The unified matches feed screen.
class MatchesFeedScreen extends ConsumerWidget {
  /// Creates the matches feed screen.
  const MatchesFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(matchesFeedProvider);
    return Scaffold(
      backgroundColor: MatchCardTokens.bgPage,
      appBar: AppBar(
        backgroundColor: MatchCardTokens.bgPage,
        foregroundColor: MatchCardTokens.textPrimary,
        elevation: 0,
        title: Text(l10n.matchesTitle, key: const Key('matches.title')),
      ),
      body: feed.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          key: Key('matches.loading'),
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => _FeedError(
          error: error,
          onRetry: () => ref.invalidate(matchesFeedProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              key: const Key('matches.empty'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.matchesEmpty,
                  key: const Key('matches.empty.message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: MatchCardTokens.textSecondary),
                ),
              ),
            );
          }
          // Group consecutive-by-round items so each open round (typically
          // exactly one fixture) gets one shared "double" selection + one
          // submit action, in the server's competition/round order.
          final groups = <String, List<MatchFeedItem>>{};
          for (final item in items) {
            groups.putIfAbsent(item.roundId, () => <MatchFeedItem>[]).add(item);
          }
          return ListView(
            key: const Key('matches.list'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              for (final entry in groups.entries)
                _RoundMatchGroup(roundId: entry.key, items: entry.value),
            ],
          );
        },
      ),
    );
  }
}

/// Renders a thrown [AppError] via `ErrorPresenter` with a retry affordance.
class _FeedError extends StatelessWidget {
  const _FeedError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  AppError get _appError => error is AppError
      ? error as AppError
      : const AppError.transient(
          'client.unexpected',
          'Something went wrong. Please try again.',
        );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appError = _appError;
    return Center(
      key: const Key('matches.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: context.tokens.error),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('matches.error.message'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: MatchCardTokens.textPrimary),
            ),
            if (ErrorPresenter.isRetryable(appError)) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('matches.error.retry'),
                onPressed: onRetry,
                child: Text(l10n.tryAgainButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One open round's card(s) — normally exactly one fixture — with its own
/// score inputs, Double toggle, and submit action. Independent of every
/// other group on the screen (its own `predictionControllerProvider(roundId)`
/// instance), so submitting one round never touches another.
class _RoundMatchGroup extends ConsumerStatefulWidget {
  const _RoundMatchGroup({required this.roundId, required this.items});

  final String roundId;
  final List<MatchFeedItem> items;

  @override
  ConsumerState<_RoundMatchGroup> createState() => _RoundMatchGroupState();
}

class _RoundMatchGroupState extends ConsumerState<_RoundMatchGroup> {
  final Map<String, TextEditingController> _home = {};
  final Map<String, TextEditingController> _away = {};

  final DateTime _now = DateTime.now().toUtc();

  String? _doubleFixtureId;
  String? _lockedDoubleFixtureId;
  bool _prefilled = false;

  bool _isLocked(RoundFixtureCardDto fixture) {
    final kickoff = fixture.kickoffAt;
    if (kickoff == null) return false;
    return !DateTime.parse(kickoff).toUtc().isAfter(_now);
  }

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      _home[item.fixture.fixtureId] = TextEditingController();
      _away[item.fixture.fixtureId] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _home.values) {
      c.dispose();
    }
    for (final c in _away.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPrefill(PredictionDto prediction) {
    if (_prefilled) return;
    final locked = <String>{
      for (final item in widget.items)
        if (_isLocked(item.fixture)) item.fixture.fixtureId,
    };
    for (final score in prediction.fixtureScores) {
      _home[score.fixtureId]?.text = '${score.homeGoals}';
      _away[score.fixtureId]?.text = '${score.awayGoals}';
      if (score.isDouble) {
        if (locked.contains(score.fixtureId)) {
          _lockedDoubleFixtureId = score.fixtureId;
        } else {
          _doubleFixtureId = score.fixtureId;
        }
      }
    }
    _prefilled = true;
  }

  void _selectDouble(String fixtureId) {
    if (_lockedDoubleFixtureId != null) return;
    setState(() => _doubleFixtureId = fixtureId);
  }

  List<FixtureScoreDto>? _collectScores() {
    final openItems = widget.items.where((i) => !_isLocked(i.fixture)).toList();
    if (openItems.isEmpty) return null;
    if (_lockedDoubleFixtureId == null && _doubleFixtureId == null) {
      return null;
    }
    final scores = <FixtureScoreDto>[];
    for (final item in openItems) {
      final fixtureId = item.fixture.fixtureId;
      final home = int.tryParse(_home[fixtureId]!.text.trim());
      final away = int.tryParse(_away[fixtureId]!.text.trim());
      if (home == null || away == null || home < 0 || away < 0) {
        return null;
      }
      scores.add(
        FixtureScoreDto(
          fixtureId: fixtureId,
          homeGoals: home,
          awayGoals: away,
          isDouble: fixtureId == _doubleFixtureId,
        ),
      );
    }
    return scores;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final submission = ref.watch(predictionControllerProvider(widget.roundId));
    final mine = ref.watch(myPredictionProvider(widget.roundId));
    final inFlight = submission is SubmissionInFlight;

    final storedPrediction = mine.value;
    if (storedPrediction != null && !_prefilled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _applyPrefill(storedPrediction));
      });
    }

    final List<FixtureScoreDto>? scores = _collectScores();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (submission is SubmissionSucceeded)
            Padding(
              key: Key('matches.success.${widget.roundId}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: _InlineBanner(
                icon: Icons.done_all,
                text: l10n.predictionSaved,
              ),
            ),
          if (submission is SubmissionFailed)
            Padding(
              key: Key('matches.errorBanner.${widget.roundId}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: _InlineBanner(
                icon: Icons.error_outline,
                text: ErrorPresenter.message(submission.error),
                isError: true,
              ),
            ),
          for (final item in widget.items)
            MatchCard(
              key: Key('matches.fixture.${item.fixture.fixtureId}'),
              leagueLabel: item.competitionName,
              fixture: item.fixture,
              locked: _isLocked(item.fixture),
              homeController: _home[item.fixture.fixtureId]!,
              awayController: _away[item.fixture.fixtureId]!,
              enabled: !inFlight,
              isDouble:
                  item.fixture.fixtureId == _doubleFixtureId ||
                  item.fixture.fixtureId == _lockedDoubleFixtureId,
              doubleSelectable:
                  !_isLocked(item.fixture) &&
                  _lockedDoubleFixtureId == null &&
                  !inFlight,
              onDoubleSelected: () => _selectDouble(item.fixture.fixtureId),
              onChanged: () => setState(() {}),
              doubleLabel: l10n.predictionDoubleLabel,
              lockedLabel: l10n.predictionFixtureLockedLabel,
            ),
          SizedBox(
            height: 44,
            child: FilledButton(
              key: Key('matches.submit.${widget.roundId}'),
              style: FilledButton.styleFrom(
                backgroundColor: context.tokens.primary,
                disabledBackgroundColor: context.tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: inFlight || scores == null
                  ? null
                  : () => ref
                        .read(
                          predictionControllerProvider(widget.roundId).notifier,
                        )
                        .submit(scores),
              child: inFlight
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.submitPredictionButton,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small inline banner (informational or error), local twin of the one on
/// the single-round prediction screen (kept private there).
class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final bg = isError ? const Color(0x33E57373) : const Color(0x2612A150);
    final fg = isError ? context.tokens.error : context.tokens.primaryLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: fg)),
          ),
        ],
      ),
    );
  }
}
