/// The per-fixture prediction screen (Axiom 4 Amendment) — browses a
/// season's linked fixtures ([seasonFixturesProvider]) and lets the caller
/// submit an independent prediction for each one, one fixture at a time
/// (no round-wide batch — see `fixture_prediction_controller.dart`'s class
/// doc). Brand-new screen, so it is built directly against ELITE OBSIDIAN
/// (`context.tokens`) rather than the legacy `MatchCardTokens` constants the
/// round-based `PredictionScreen` still uses.
///
/// There is deliberately no "already predicted" pre-fill: the server does
/// not yet expose a per-fixture read (only the `POST .../prediction` submit
/// endpoint exists as of Phase 7.2 — see `fixture_prediction_providers.dart`
/// file doc), so every fixture's fields start blank each time this screen
/// opens. Submitting again for an already-predicted fixture still works
/// (the server idempotently amends), it just isn't visually indicated here.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import '../leaderboards/season_leaderboard_screen.dart';
import 'fixture_prediction_controller.dart';
import 'fixture_prediction_providers.dart';
import 'fixture_prediction_submission.dart';

/// The fixture-list/predict screen for a single season.
class FixturePredictionScreen extends ConsumerWidget {
  /// Creates the fixture prediction screen for [seasonId].
  const FixturePredictionScreen({
    required this.seasonId,
    required this.seasonLabel,
    super.key,
  });

  /// The season whose linked fixtures are browsed and predicted.
  final String seasonId;

  /// The season's display label (for the leaderboard app-bar action).
  final String seasonLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fixtures = ref.watch(seasonFixturesProvider(seasonId));
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(
          l10n.fixturePredictionTitle,
          key: const Key('fixturePrediction.title'),
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('fixturePrediction.viewLeaderboard'),
            tooltip: l10n.viewLeaderboardTooltip,
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SeasonLeaderboardScreen(
                  seasonId: seasonId,
                  seasonLabel: seasonLabel,
                ),
              ),
            ),
          ),
        ],
      ),
      body: fixtures.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => _FixturePredictionError(
          error: error,
          onRetry: () => ref.invalidate(seasonFixturesProvider(seasonId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              key: const Key('fixturePrediction.empty'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.fixturePredictionEmptyMessage,
                  key: const Key('fixturePrediction.empty.message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            key: const Key('fixturePrediction.list'),
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) => _FixturePredictionCard(
              seasonId: seasonId,
              fixture: list[index],
            ),
          );
        },
      ),
    );
  }
}

/// Renders a thrown [AppError] via `ErrorPresenter` with a retry affordance.
class _FixturePredictionError extends StatelessWidget {
  const _FixturePredictionError({required this.error, required this.onRetry});

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
    final tokens = context.tokens;
    return Center(
      key: const Key('fixturePrediction.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: tokens.error),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('fixturePrediction.error.message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textPrimary),
            ),
            if (ErrorPresenter.isRetryable(appError)) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('fixturePrediction.error.retry'),
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

/// One fixture's own editable card: team names, kickoff, a home/away score
/// pair, a "double" toggle, and its own submit button — this fixture's
/// submit lifecycle is entirely independent of every other card on screen
/// (`fixturePredictionControllerProvider` is a family keyed per fixture).
class _FixturePredictionCard extends ConsumerStatefulWidget {
  const _FixturePredictionCard({required this.seasonId, required this.fixture});

  final String seasonId;
  final SeasonFixtureCardDto fixture;

  @override
  ConsumerState<_FixturePredictionCard> createState() =>
      _FixturePredictionCardState();
}

class _FixturePredictionCardState
    extends ConsumerState<_FixturePredictionCard> {
  final TextEditingController _home = TextEditingController();
  final TextEditingController _away = TextEditingController();
  bool _isDouble = false;

  @override
  void dispose() {
    _home.dispose();
    _away.dispose();
    super.dispose();
  }

  bool get _isLocked {
    final kickoff = widget.fixture.kickoffAt;
    if (kickoff == null) return false;
    final parsed = DateTime.tryParse(kickoff)?.toUtc();
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now().toUtc());
  }

  FixturePredictionKey get _key =>
      (seasonId: widget.seasonId, fixtureId: widget.fixture.fixtureId);

  void _submit() {
    final home = int.tryParse(_home.text.trim());
    final away = int.tryParse(_away.text.trim());
    if (home == null || away == null || home < 0 || away < 0) {
      return;
    }
    ref
        .read(fixturePredictionControllerProvider(_key).notifier)
        .submit(homeGoals: home, awayGoals: away, isDouble: _isDouble);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final submission = ref.watch(fixturePredictionControllerProvider(_key));
    final inFlight = submission is FixtureSubmissionInFlight;
    final locked = _isLocked;
    final enabled = !inFlight && !locked;

    final home = widget.fixture.homeTeam ?? '?';
    final away = widget.fixture.awayTeam ?? '?';

    return Container(
      key: Key('fixturePrediction.fixture.${widget.fixture.fixtureId}'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$home  vs  $away',
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.predictionFixtureLockedLabel,
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: Key(
                    'fixturePrediction.home.${widget.fixture.fixtureId}',
                  ),
                  controller: _home,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Text('—', style: TextStyle(color: tokens.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: Key(
                    'fixturePrediction.away.${widget.fixture.fixtureId}',
                  ),
                  controller: _away,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Checkbox(
                key: Key(
                  'fixturePrediction.double.${widget.fixture.fixtureId}',
                ),
                value: _isDouble,
                onChanged: enabled
                    ? (v) => setState(() => _isDouble = v ?? false)
                    : null,
              ),
              Text(
                l10n.predictionDoubleLabel,
                style: TextStyle(color: tokens.textSecondary),
              ),
              const Spacer(),
              FilledButton(
                key: Key(
                  'fixturePrediction.submit.${widget.fixture.fixtureId}',
                ),
                onPressed: enabled ? _submit : null,
                child: inFlight
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.submitFixturePredictionButton),
              ),
            ],
          ),
          if (submission is FixtureSubmissionSucceeded)
            Padding(
              key: Key('fixturePrediction.success.${widget.fixture.fixtureId}'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.fixturePredictionSavedMessage,
                style: TextStyle(color: tokens.primary, fontSize: 12),
              ),
            ),
          if (submission is FixtureSubmissionFailed)
            Padding(
              key: Key('fixturePrediction.failure.${widget.fixture.fixtureId}'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                ErrorPresenter.message(submission.error),
                key: Key(
                  'fixturePrediction.failure.message.${widget.fixture.fixtureId}',
                ),
                style: TextStyle(color: tokens.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
