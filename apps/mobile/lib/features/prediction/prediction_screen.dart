/// The Prediction **submit** screen — Fotmob-style dark match cards.
///
/// Reuses the exact same reads/controller and preserves every widget `Key`
/// used by the existing tests. Only the *visual* layer of the fixture row was
/// rebuilt into a dark match card (color-bleed glow + +/?/− steppers + a neon
/// "Double" pill under the predict controls), per the design report.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../l10n/app_localizations.dart';
import '../../core/error/error_presenter.dart';
import '../competition/competition_providers.dart';
import '../competition/round_status_label.dart';
import 'match_card.dart';
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
      backgroundColor: MatchCardTokens.bgPage,
      appBar: AppBar(
        backgroundColor: MatchCardTokens.bgPage,
        foregroundColor: MatchCardTokens.textPrimary,
        elevation: 0,
        title: Text(l10n.predictionTitle, key: const Key('prediction.title')),
      ),
      body: round.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => _FormError(
          error: error,
          onRetry: () => ref.invalidate(roundDetailProvider(roundId)),
        ),
        data: (r) => _RoundBody(round: r),
      ),
    );
  }
}

/// Renders the round header and, when the round is open, the prediction form.
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
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('prediction.roundHeader'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: const Color(0xFF141414),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.roundItemTitle(round.sequence),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: MatchCardTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${roundStatusLabel(l10n, round.status)} · Rules v${round.rulesetVersion}',
            style: const TextStyle(
              color: MatchCardTokens.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the round is not open for predictions (locked or scored).
class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.round});

  final RoundDto round;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('prediction.closed'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.lock_clock_outlined,
              size: 48,
              color: MatchCardTokens.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.predictionClosedMessage(
                roundStatusLabel(l10n, round.status).toLowerCase(),
              ),
              key: const Key('prediction.closed.message'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: MatchCardTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The editable prediction form.
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
                style: const TextStyle(color: MatchCardTokens.textSecondary),
              ),
            ),
          );
        }
        return _PredictionEditor(roundId: roundId, fixtures: list);
      },
    );
  }
}

/// Renders a thrown [AppError] via `ErrorPresenter` with a retry affordance.
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
    final appError = _appError;
    return Center(
      key: const Key('browse.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFE57373)),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('browse.error.message'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: MatchCardTokens.textPrimary),
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

/// The stateful editor over the resolved fixtures.
class _PredictionEditor extends ConsumerStatefulWidget {
  const _PredictionEditor({required this.roundId, required this.fixtures});

  final String roundId;
  final List<RoundFixtureCardDto> fixtures;

  @override
  ConsumerState<_PredictionEditor> createState() => _PredictionEditorState();
}

class _PredictionEditorState extends ConsumerState<_PredictionEditor> {
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

  void _selectDouble(String fixtureId) {
    if (_lockedDoubleFixtureId != null) return;
    setState(() => _doubleFixtureId = fixtureId);
  }

  void _submit(List<FixtureScoreDto> scores) {
    ref
        .read(predictionControllerProvider(widget.roundId).notifier)
        .submit(scores);
  }

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

    final storedPrediction = mine.value;
    if (storedPrediction != null && !_prefilled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _applyPrefill(storedPrediction));
      });
    }

    final openFixtures = widget.fixtures.where((f) => !_isLocked(f)).toList();
    final List<FixtureScoreDto>? scores = _collectScores();
    final bool noDoubleChosen =
        _lockedDoubleFixtureId == null && _doubleFixtureId == null;

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              key: const Key('prediction.form'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 20),
                if (scores == null && openFixtures.isNotEmpty)
                  Padding(
                    key: const Key('prediction.incompleteHint'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      noDoubleChosen
                          ? l10n.predictionDoubleHint
                          : l10n.predictionIncompleteHint,
                      key: const Key('prediction.incompleteHint.text'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE57373)),
                    ),
                  ),
                if (mine.value != null)
                  Padding(
                    key: const Key('prediction.alreadySubmitted'),
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _Banner(
                      icon: Icons.check_circle_outline,
                      text: l10n.predictionAlreadySubmitted,
                    ),
                  ),
                if (submission is SubmissionSucceeded)
                  Padding(
                    key: const Key('prediction.success'),
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _Banner(
                      icon: Icons.done_all,
                      text: l10n.predictionSaved,
                    ),
                  ),
                if (submission is SubmissionFailed)
                  Padding(
                    key: const Key('prediction.errorBanner'),
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _Banner(
                      icon: Icons.error_outline,
                      text: ErrorPresenter.message(submission.error),
                      isError: true,
                    ),
                  ),
                if (openFixtures.isEmpty)
                  Padding(
                    key: const Key('prediction.noOpenFixtures'),
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _Banner(
                      icon: Icons.lock_clock_outlined,
                      text: l10n.predictionNoOpenFixturesMessage,
                    ),
                  ),
                for (final fixture in widget.fixtures)
                  MatchCard(
                    key: Key('prediction.fixture.${fixture.fixtureId}'),
                    leagueLabel: l10n.roundFixturesTitle,
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
                    doubleLabel: l10n.predictionDoubleLabel,
                    lockedLabel: l10n.predictionFixtureLockedLabel,
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SubmitButton(
                  inFlight: inFlight,
                  onSubmit: scores == null ? null : () => _submit(scores),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The submit affordance.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.inFlight, required this.onSubmit});

  final bool inFlight;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 52,
      child: FilledButton(
        key: const Key('prediction.submit'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF12A150),
          disabledBackgroundColor: const Color(0xFF1F1F22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: inFlight ? null : onSubmit,
        child: inFlight
            ? const SizedBox(
                key: Key('prediction.submit.spinner'),
                height: 20,
                width: 20,
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
                  fontSize: 15,
                ),
              ),
      ),
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
    final bg = isError ? const Color(0x33E57373) : const Color(0x2612A150);
    final fg = isError ? const Color(0xFFE57373) : const Color(0xFF4ADE80);
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
