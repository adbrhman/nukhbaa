/// The Prediction **submit** screen — render the open round + its fixtures and
/// let the caller enter (or amend) one predicted scoreline per fixture.
///
/// ## Composition (reuses the Competition browse reads — no duplication)
/// Four watched reads drive this screen; the three read providers are the exact
/// ones the Competition browse slice already owns:
///   * `roundDetailProvider(roundId)`   — the round header + lifecycle status.
///     The submit form is offered ONLY while the round is `open`; a `locked` /
///     `scored` round shows a read-only "closed" notice (the server would refuse
///     a late submit with `prediction.round_not_open`, but the UI does not even
///     present the affordance once the round has left `open`).
///   * `roundFixturesProvider(roundId)` — the fixtures to build one score input
///     per fixture, in display order.
///   * `myPredictionProvider(roundId)`  — the caller's own stored prediction (or
///     `null` when not yet submitted). Non-null → the form pre-fills each
///     fixture with the stored scoreline and the screen shows an "already
///     submitted" banner (amending is the same submit call — one row per
///     `(participant, round)`, Axiom 4).
///   * `predictionControllerProvider(roundId)` — the [SubmissionState] this
///     screen switches over to disable inputs while `InFlight`, confirm on
///     `Succeeded`, and render a typed failure via `ErrorPresenter` on `Failed`.
///
/// ## Integrity boundary (Axioms 2/5)
/// The screen collects only goal integers per fixture and submits them as
/// `List<FixtureScoreDto>` through the controller → `api_client`. It never
/// computes or displays points, never sends a participant id, and never writes
/// to Supabase directly (ADR-002 §2.2/§2.8) — every submission is the server
/// use-case API. Error copy is produced solely by `ErrorPresenter`; the widget
/// never branches on raw `code` strings.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../core/error/error_presenter.dart';
import '../competition/competition_providers.dart';
import '../competition/season_rounds_screen.dart' show roundStatusLabel;
import '../competition/widgets/async_list_view.dart';
import 'prediction_controller.dart';
import 'prediction_providers.dart';
import 'prediction_submission.dart';

/// The lifecycle status token for a round that is open for predictions.
const String _roundStatusOpen = 'open';

/// The prediction submit/amend screen for a single round.
class PredictionScreen extends ConsumerWidget {
  /// Creates the prediction screen for [roundId].
  const PredictionScreen({required this.roundId, super.key});

  /// The round the caller predicts.
  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final round = ref.watch(roundDetailProvider(roundId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.predictionTitle, key: const Key('prediction.title')),
      ),
      // The round header must resolve first (a not-found round surfaces here);
      // only an OPEN round shows the fixtures + form below it.
      body: AsyncObjectView<RoundDto>(
        value: round,
        onRetry: () => ref.invalidate(roundDetailProvider(roundId)),
        builder: (context, r) => _RoundBody(round: r),
      ),
    );
  }
}

/// Renders the round header and, when the round is open, the prediction form;
/// otherwise a read-only "closed" notice.
class _RoundBody extends StatelessWidget {
  const _RoundBody({required this.round});

  final RoundDto round;

  @override
  Widget build(BuildContext context) {
    final isOpen = round.status == _roundStatusOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RoundHeader(round: round),
        const Divider(height: 1),
        if (isOpen)
          Expanded(child: _PredictionForm(roundId: round.id))
        else
          Expanded(child: _ClosedNotice(round: round)),
      ],
    );
  }
}

/// A compact header describing the round being predicted.
class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.round});

  final RoundDto round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('prediction.roundHeader'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.roundItemTitle(round.sequence),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${roundStatusLabel(l10n, round.status)} · Rules v${round.rulesetVersion}',
          ),
        ],
      ),
    );
  }
}

/// Shown when the round is not open for predictions (locked or scored): the
/// submit affordance is deliberately absent.
class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.round});

  final RoundDto round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('prediction.closed'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_clock_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              l10n.predictionClosedMessage(
                roundStatusLabel(l10n, round.status).toLowerCase(),
              ),
              key: const Key('prediction.closed.message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The editable prediction form.
///
/// The prediction form is a single stateful unit over the *entire* fixture set
/// (it needs all fixtures at once plus the stored prediction + submit surface),
/// so it cannot use the per-row [AsyncListView]. Instead it reproduces
/// [AsyncListView]'s exact loading / legitimate-empty / error affordances (same
/// keys and `ErrorPresenter` rendering) for visual consistency, then hands the
/// resolved non-empty list to the stateful [_PredictionEditor].
class _PredictionForm extends ConsumerWidget {
  const _PredictionForm({required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fixtures = ref.watch(roundFixturesProvider(roundId));
    return fixtures.when(
      skipLoadingOnRefresh: false,
      loading: () => const Center(
        key: Key('browse.loading'),
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => _FormError(
        error: error,
        onRetry: () => ref.invalidate(roundFixturesProvider(roundId)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            key: const Key('browse.empty'),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.roundFixturesEmpty,
                key: const Key('browse.empty.message'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return _PredictionEditor(roundId: roundId, fixtures: list);
      },
    );
  }
}

/// Renders a thrown [AppError] via `ErrorPresenter` with a retry affordance when
/// retryable — mirrors `async_list_view.dart`'s error surface for the form.
class _FormError extends StatelessWidget {
  const _FormError({required this.error, required this.onRetry});

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
    final scheme = Theme.of(context).colorScheme;
    final appError = _appError;
    return Center(
      key: const Key('browse.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('browse.error.message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface),
            ),
            if (ErrorPresenter.isRetryable(appError)) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('browse.error.retry'),
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

/// The stateful editor over the resolved fixtures: holds per-fixture home/away
/// goal inputs, pre-fills them from any existing prediction, disables everything
/// while a submit is in flight, and drives [PredictionController.submit].
class _PredictionEditor extends ConsumerStatefulWidget {
  const _PredictionEditor({required this.roundId, required this.fixtures});

  final String roundId;
  final List<RoundFixtureCardDto> fixtures;

  @override
  ConsumerState<_PredictionEditor> createState() => _PredictionEditorState();
}

class _PredictionEditorState extends ConsumerState<_PredictionEditor> {
  /// Per-fixture home/away controllers, keyed by fixture id, in the fixtures'
  /// display order.
  final Map<String, TextEditingController> _home = {};
  final Map<String, TextEditingController> _away = {};

  /// The instant used to decide which fixtures have already kicked off,
  /// captured once when the editor mounts so a fixture never flips from open
  /// to locked mid-edit while the user is filling the form (Session decision
  /// 2026-08-07: per-fixture kickoff lock, independent of the round's admin
  /// lock).
  final DateTime _now = DateTime.now().toUtc();

  /// The fixture id currently marked as the caller's double among the OPEN
  /// fixtures, or `null` if none is selected yet.
  String? _doubleFixtureId;

  /// The fixture id of an ALREADY-LOCKED fixture that carries the double,
  /// carried over from a prior submission — once a fixture locks, its double
  /// (if any) can never move to an open fixture (the merged forecast would
  /// then carry two).
  String? _lockedDoubleFixtureId;

  /// Whether the pre-fill from the stored prediction has already been applied
  /// (so a rebuild does not clobber the user's in-progress edits).
  bool _prefilled = false;

  /// Whether [fixture] has already kicked off as of [_now]. A fixture with no
  /// registered schedule is treated as NOT locked (mirrors the server rule).
  bool _isLocked(RoundFixtureCardDto fixture) {
    final kickoff = fixture.kickoffAt;
    if (kickoff == null) return false;
    return !DateTime.parse(kickoff).toUtc().isAfter(_now);
  }

  @override
  void initState() {
    super.initState();
    for (final fixture in widget.fixtures) {
      _home[fixture.fixtureId] = TextEditingController();
      _away[fixture.fixtureId] = TextEditingController();
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

  /// Applies the stored prediction's scorelines to the inputs exactly once,
  /// and restores which fixture (if any) was marked as the double — an
  /// already-locked double is tracked separately since it can no longer move.
  void _applyPrefill(PredictionDto prediction) {
    if (_prefilled) return;
    final locked = {
      for (final fixture in widget.fixtures)
        if (_isLocked(fixture)) fixture.fixtureId,
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

  /// Moves the double to [fixtureId] (single-select — any previous open
  /// selection is cleared automatically). A no-op while a locked fixture
  /// already carries the double.
  void _selectDouble(String fixtureId) {
    if (_lockedDoubleFixtureId != null) return;
    setState(() => _doubleFixtureId = fixtureId);
  }

  /// Reads the current inputs into the wire command shape, in fixtures'
  /// display order, OPEN fixtures only — a locked fixture's stored score is
  /// carried over automatically by the server (Session decision 2026-08-07)
  /// and is never resubmitted. Returns `null` while any open fixture is
  /// missing a valid non-negative goal count, no open fixture is left to
  /// predict, or no double is selected and none is already locked in — the
  /// submit button stays disabled in every one of those cases.
  List<FixtureScoreDto>? _collectScores() {
    final openFixtures = widget.fixtures.where((f) => !_isLocked(f)).toList();
    if (openFixtures.isEmpty) return null;
    if (_lockedDoubleFixtureId == null && _doubleFixtureId == null) {
      return null;
    }

    final scores = <FixtureScoreDto>[];
    for (final fixture in openFixtures) {
      final home = int.tryParse(_home[fixture.fixtureId]!.text.trim());
      final away = int.tryParse(_away[fixture.fixtureId]!.text.trim());
      if (home == null || away == null || home < 0 || away < 0) {
        return null;
      }
      scores.add(
        FixtureScoreDto(
          fixtureId: fixture.fixtureId,
          homeGoals: home,
          awayGoals: away,
          isDouble: fixture.fixtureId == _doubleFixtureId,
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

    // Pre-fill from the stored prediction (once) when it resolves non-null.
    // Scheduled via `addPostFrameCallback` rather than mutating the
    // controllers inline here: by the time `myPrediction` resolves (an
    // async fetch), this row's `TextField`s are already mounted from a
    // prior frame, so writing `.text` directly during build would notify
    // their listeners — and call `setState`/`markNeedsBuild` on
    // already-built elements — while the framework's build phase is still
    // locked, throwing "setState() or markNeedsBuild() called during
    // build" and hanging the screen every time an already-predicted round
    // is opened. Deferring to the post-frame callback runs it once the
    // build phase is unlocked, so the same mutation is safe there.
    final storedPrediction = mine.value;
    if (storedPrediction != null && !_prefilled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _applyPrefill(storedPrediction));
      });
    }

    final openFixtures = widget.fixtures.where((f) => !_isLocked(f)).toList();

    // Collect the current inputs once per build: `null` when the form is not
    // yet submittable (an open fixture missing a score, no double selected, or
    // nothing open left to predict), otherwise the exact wire command the
    // controller submits. Computing it once avoids re-parsing the same fields
    // twice on every rebuild.
    final List<FixtureScoreDto>? scores = _collectScores();

    return ListView(
      key: const Key('prediction.form'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // "Already submitted" banner (amending is the same submit call).
        if (mine.value != null)
          Padding(
            key: const Key('prediction.alreadySubmitted'),
            padding: const EdgeInsets.only(bottom: 16),
            child: _Banner(
              icon: Icons.check_circle_outline,
              text: l10n.predictionAlreadySubmitted,
            ),
          ),
        // The success confirmation, shown after a 200.
        if (submission is SubmissionSucceeded)
          Padding(
            key: const Key('prediction.success'),
            padding: const EdgeInsets.only(bottom: 16),
            child: _Banner(icon: Icons.done_all, text: l10n.predictionSaved),
          ),
        // A typed failure, presented via ErrorPresenter (never raw codes).
        if (submission is SubmissionFailed)
          Padding(
            key: const Key('prediction.errorBanner'),
            padding: const EdgeInsets.only(bottom: 16),
            child: _Banner(
              icon: Icons.error_outline,
              text: ErrorPresenter.message(submission.error),
              isError: true,
            ),
          ),
        if (openFixtures.isEmpty)
          Padding(
            key: const Key('prediction.noOpenFixtures'),
            padding: const EdgeInsets.only(bottom: 16),
            child: _Banner(
              icon: Icons.lock_clock_outlined,
              text: l10n.predictionNoOpenFixturesMessage,
            ),
          ),
        for (final fixture in widget.fixtures)
          _FixtureScoreInput(
            key: Key('prediction.fixture.${fixture.fixtureId}'),
            fixture: fixture,
            locked: _isLocked(fixture),
            homeController: _home[fixture.fixtureId]!,
            awayController: _away[fixture.fixtureId]!,
            enabled: !inFlight,
            isDouble:
                fixture.fixtureId == _doubleFixtureId ||
                fixture.fixtureId == _lockedDoubleFixtureId,
            doubleSelectable:
                !_isLocked(fixture) &&
                _lockedDoubleFixtureId == null &&
                !inFlight,
            onDoubleSelected: () => _selectDouble(fixture.fixtureId),
            onChanged: () => setState(() {}),
          ),
        const SizedBox(height: 8),
        if (scores == null && openFixtures.isNotEmpty)
          Padding(
            key: const Key('prediction.incompleteHint'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _lockedDoubleFixtureId == null && _doubleFixtureId == null
                  ? l10n.predictionDoubleHint
                  : l10n.predictionIncompleteHint,
              key: const Key('prediction.incompleteHint.text'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        _SubmitButton(
          inFlight: inFlight,
          onSubmit: scores == null
              ? null
              : () => ref
                    .read(predictionControllerProvider(widget.roundId).notifier)
                    .submit(scores),
        ),
      ],
    );
  }
}

/// One fixture's home/away goal inputs, plus (for an open fixture) the
/// double-selection star.
class _FixtureScoreInput extends StatelessWidget {
  const _FixtureScoreInput({
    required this.fixture,
    required this.locked,
    required this.homeController,
    required this.awayController,
    required this.enabled,
    required this.isDouble,
    required this.doubleSelectable,
    required this.onDoubleSelected,
    required this.onChanged,
    super.key,
  });

  final RoundFixtureCardDto fixture;

  /// Whether this fixture has already kicked off — its score inputs render
  /// disabled and it never gets a tappable double star.
  final bool locked;
  final TextEditingController homeController;
  final TextEditingController awayController;
  final bool enabled;

  /// Whether this fixture is currently the caller's double (open selection
  /// or an already-locked one carried over).
  final bool isDouble;

  /// Whether the double star is tappable for this fixture (open, not locked,
  /// no submit in flight, and no already-locked fixture holds the double).
  final bool doubleSelectable;
  final VoidCallback onDoubleSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final home = fixture.homeTeam;
    final away = fixture.awayTeam;
    final title = home != null && away != null
        ? l10n.fixtureVsTitle(home, away)
        : l10n.fixtureItemTitle(fixture.fixtureId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          IconButton(
            key: Key('prediction.double.${fixture.fixtureId}'),
            icon: Icon(isDouble ? Icons.star : Icons.star_border),
            tooltip: l10n.predictionDoubleLabel,
            color: isDouble
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            onPressed: doubleSelectable ? onDoubleSelected : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, overflow: TextOverflow.ellipsis),
                if (locked)
                  Text(
                    l10n.predictionFixtureLockedLabel,
                    key: Key('prediction.locked.${fixture.fixtureId}'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _GoalField(
            key: Key('prediction.home.${fixture.fixtureId}'),
            controller: homeController,
            enabled: enabled && !locked,
            onChanged: onChanged,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('-'),
          ),
          _GoalField(
            key: Key('prediction.away.${fixture.fixtureId}'),
            controller: awayController,
            enabled: enabled && !locked,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A narrow numeric field constrained to digits (a goal count).
class _GoalField extends StatelessWidget {
  const _GoalField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: const InputDecoration(
          counterText: '',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// The submit affordance. Disabled (null [onSubmit]) until every fixture has a
/// valid goal count, and shows a spinner while a submit is in flight.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.inFlight, required this.onSubmit});

  final bool inFlight;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FilledButton(
      key: const Key('prediction.submit'),
      onPressed: inFlight ? null : onSubmit,
      child: inFlight
          ? const SizedBox(
              key: Key('prediction.submit.spinner'),
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(l10n.submitPredictionButton),
    );
  }
}

/// A small inline banner (informational or error).
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.isError = false});

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isError ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = isError ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: fg)),
          ),
        ],
      ),
    );
  }
}
