/// The regular user's unified **current month** screen (Monthly
/// Competitions transition, `docs/project-context.md` §9) — every public
/// competition's current-month fixture in one flat, no-picker list. This is
/// the screen `AccountScreen`'s "المباريات" (`account.matches`) button opens
/// instead of the Round-based `MatchesFeedScreen`.
///
/// Reuses the existing per-fixture submit slice exactly as-is, unmodified:
///   * [fixturePredictionControllerProvider] / [FixtureSubmissionState] from
///     `fixture_prediction_controller.dart` / `fixture_prediction_submission.dart`
///     — the same controller the season-scoped `FixturePredictionScreen`
///     already uses, keyed by the same `(seasonId, fixtureId)` pair. Each
///     `CurrentMonthFixtureItemDto.fixture` already carries its own
///     `seasonId`, so this screen needs no separate season lookup.
///
/// Only the read is new: [currentMonthFixturesProvider]
/// (`GET /feed/current-month-fixtures`, `current_month_fixtures_providers.dart`).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import 'current_month_fixtures_providers.dart';
import 'fixture_prediction_controller.dart';
import 'fixture_prediction_submission.dart';

/// The current-month fixtures screen.
class CurrentMonthFixturesScreen extends ConsumerWidget {
  /// Creates the current-month fixtures screen.
  const CurrentMonthFixturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(currentMonthFixturesProvider);
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(
          l10n.matchesTitle,
          key: const Key('currentMonthFixtures.title'),
        ),
      ),
      body: feed.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          key: Key('currentMonthFixtures.loading'),
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => _CurrentMonthFixturesError(
          error: error,
          onRetry: () => ref.invalidate(currentMonthFixturesProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              key: const Key('currentMonthFixtures.empty'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.matchesEmpty,
                  key: const Key('currentMonthFixtures.empty.message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            key: const Key('currentMonthFixtures.list'),
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _CurrentMonthFixtureCard(item: items[index]),
          );
        },
      ),
    );
  }
}

/// Renders a thrown [AppError] via `ErrorPresenter` with a retry affordance.
class _CurrentMonthFixturesError extends StatelessWidget {
  const _CurrentMonthFixturesError({
    required this.error,
    required this.onRetry,
  });

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
      key: const Key('currentMonthFixtures.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: tokens.error),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('currentMonthFixtures.error.message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textPrimary),
            ),
            if (ErrorPresenter.isRetryable(appError)) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('currentMonthFixtures.error.retry'),
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

/// One fixture's card: owning competition label, team names, kickoff, a
/// home/away score pair, a "double" toggle, and its own submit action —
/// entirely independent of every other card on screen
/// (`fixturePredictionControllerProvider` is a family keyed per
/// `(seasonId, fixtureId)`).
class _CurrentMonthFixtureCard extends ConsumerStatefulWidget {
  const _CurrentMonthFixtureCard({required this.item});

  final CurrentMonthFixtureItemDto item;

  @override
  ConsumerState<_CurrentMonthFixtureCard> createState() =>
      _CurrentMonthFixtureCardState();
}

class _CurrentMonthFixtureCardState
    extends ConsumerState<_CurrentMonthFixtureCard> {
  final TextEditingController _home = TextEditingController();
  final TextEditingController _away = TextEditingController();
  bool _isDouble = false;

  @override
  void dispose() {
    _home.dispose();
    _away.dispose();
    super.dispose();
  }

  SeasonFixtureCardDto get _fixture => widget.item.fixture;

  bool get _isLocked {
    final kickoff = _fixture.kickoffAt;
    if (kickoff == null) return false;
    final parsed = DateTime.tryParse(kickoff)?.toUtc();
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now().toUtc());
  }

  FixturePredictionKey get _key =>
      (seasonId: _fixture.seasonId, fixtureId: _fixture.fixtureId);

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

    final home = _fixture.homeTeam ?? '?';
    final away = _fixture.awayTeam ?? '?';

    return Container(
      key: Key('currentMonthFixtures.fixture.${_fixture.fixtureId}'),
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
            widget.item.competitionName,
            key: Key('currentMonthFixtures.competition.${_fixture.fixtureId}'),
            style: TextStyle(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
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
                  key: Key('currentMonthFixtures.home.${_fixture.fixtureId}'),
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
                  key: Key('currentMonthFixtures.away.${_fixture.fixtureId}'),
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
                key: Key('currentMonthFixtures.double.${_fixture.fixtureId}'),
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
                key: Key('currentMonthFixtures.submit.${_fixture.fixtureId}'),
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
              key: Key('currentMonthFixtures.success.${_fixture.fixtureId}'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.fixturePredictionSavedMessage,
                style: TextStyle(color: tokens.primary, fontSize: 12),
              ),
            ),
          if (submission is FixtureSubmissionFailed)
            Padding(
              key: Key('currentMonthFixtures.failure.${_fixture.fixtureId}'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                ErrorPresenter.message(submission.error),
                key: Key(
                  'currentMonthFixtures.failure.message.${_fixture.fixtureId}',
                ),
                style: TextStyle(color: tokens.error, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
