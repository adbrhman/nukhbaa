/// The Prediction **submit** screen — Fotmob-style dark match cards.
///
/// Reuses the exact same reads/controller and preserves every widget `Key`
/// used by the existing tests. Only the *visual* layer of the fixture row was
/// rebuilt into a dark match card (color-bleed glow + +/?/− steppers + a neon
/// "Double" pill under the predict controls), per the design report.
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
import 'prediction_controller.dart';
import 'prediction_providers.dart';
import 'prediction_submission.dart';

/// The lifecycle status token for a round that is open for predictions.
const String _roundStatusOpen = 'open';

// ─────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors the CSS variables from the design report).
// ─────────────────────────────────────────────────────────────────────────
class _Tokens {
  static const Color bgPage = Color(0xFF0A0A0A);
  static const Color cardGradStart = Color(0xE6281E1E); // rgba(40,30,30,.9)
  static const Color cardGradEnd = Color(0xE61C2028); // rgba(28,32,40,.9)

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textTertiary = Color(0xFF6E6E73);

  static const Color btnBg = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const Color btnBorder = Color(0x14FFFFFF); // rgba(255,255,255,.08)

  static const Color doubleInactiveBg = Color(0x0FFFFFFF);
  static const Color doubleActiveBg = Color(0x26FFD700); // rgba(255,215,0,.15)
  static const Color doubleGlow = Color(0xFFFFD700);

  static const double cardRadius = 16;
  static const double logoSize = 48;
}

/// A small palette to derive a stable "team color" from a team name, used for
/// both the round logo initials and the color-bleed glow (no logo assets exist
/// in the DTO — team names + kickoff are the only fixture identity available).
Color _teamColor(String? name) {
  if (name == null || name.isEmpty) return const Color(0xFF3A3A3C);
  const palette = <Color>[
    Color(0xFFE30613), // red
    Color(0xFF1D428A), // blue
    Color(0xFFF5A12D), // orange
    Color(0xFF132257), // navy
    Color(0xFF78D0F1), // light blue
    Color(0xFF2E7D32), // green
    Color(0xFF6A1B9A), // purple
    Color(0xFF00897B), // teal
    Color(0xFFC2185B), // pink
    Color(0xFFEF6C00), // deep orange
  ];
  var hash = 0;
  for (final code in name.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

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
      backgroundColor: _Tokens.bgPage,
      appBar: AppBar(
        backgroundColor: _Tokens.bgPage,
        foregroundColor: _Tokens.textPrimary,
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
              color: _Tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${roundStatusLabel(l10n, round.status)} · Rules v${round.rulesetVersion}',
            style: const TextStyle(color: _Tokens.textSecondary, fontSize: 13),
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
              color: _Tokens.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.predictionClosedMessage(
                roundStatusLabel(l10n, round.status).toLowerCase(),
              ),
              key: const Key('prediction.closed.message'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _Tokens.textSecondary),
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
                style: const TextStyle(color: _Tokens.textSecondary),
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
              style: const TextStyle(color: _Tokens.textPrimary),
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

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            key: const Key('prediction.form'),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: <Widget>[
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
                _MatchCard(
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
              const SizedBox(height: 4),
              if (scores == null && openFixtures.isNotEmpty)
                Padding(
                  key: const Key('prediction.incompleteHint'),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _lockedDoubleFixtureId == null && _doubleFixtureId == null
                        ? l10n.predictionDoubleHint
                        : l10n.predictionIncompleteHint,
                    key: const Key('prediction.incompleteHint.text'),
                    style: const TextStyle(color: Color(0xFFE57373)),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _SubmitButton(
              inFlight: inFlight,
              onSubmit: scores == null
                  ? null
                  : () => ref
                        .read(
                          predictionControllerProvider(widget.roundId).notifier,
                        )
                        .submit(scores),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single Fotmob-style dark match card with color-bleed glow, two teams, the
/// +/?/− steppers per side, and a neon "Double" pill under the controls.
class _MatchCard extends StatelessWidget {
  const _MatchCard({
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
  final bool locked;
  final TextEditingController homeController;
  final TextEditingController awayController;
  final bool enabled;
  final bool isDouble;
  final bool doubleSelectable;
  final VoidCallback onDoubleSelected;
  final VoidCallback onChanged;

  String _kickoffLabel() {
    final k = fixture.kickoffAt;
    if (k == null) return '';
    final dt = DateTime.tryParse(k)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final homeColor = _teamColor(fixture.homeTeam);
    final awayColor = _teamColor(fixture.awayTeam);
    final home = fixture.homeTeam ?? '?';
    final away = fixture.awayTeam ?? '?';
    final kickoff = _kickoffLabel();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_Tokens.cardRadius),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_Tokens.cardGradStart, _Tokens.cardGradEnd],
        ),
      ),
      child: Stack(
        children: <Widget>[
          // Color-bleed glow, left (home).
          Positioned(
            left: -30,
            top: 0,
            bottom: 0,
            child: _GlowBlob(color: homeColor),
          ),
          // Color-bleed glow, right (away).
          Positioned(
            right: -30,
            top: 0,
            bottom: 0,
            child: _GlowBlob(color: awayColor),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                // Header: league line + external icon placeholder.
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.sports_soccer,
                      size: 16,
                      color: _Tokens.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kickoff.isEmpty
                            ? l10n.roundFixturesTitle
                            : '${l10n.roundFixturesTitle} • $kickoff',
                        style: const TextStyle(
                          color: _Tokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (locked)
                      const Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: _Tokens.textTertiary,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Body: home team | predict controls | away team.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _TeamColumn(name: home, color: homeColor),
                    ),
                    const SizedBox(width: 8),
                    _PredictCenter(
                      fixtureId: fixture.fixtureId,
                      homeController: homeController,
                      awayController: awayController,
                      enabled: enabled && !locked,
                      isDouble: isDouble,
                      doubleSelectable: doubleSelectable,
                      onDoubleSelected: onDoubleSelected,
                      onChanged: onChanged,
                      doubleLabel: l10n.predictionDoubleLabel,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TeamColumn(name: away, color: awayColor),
                    ),
                  ],
                ),
                if (locked) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.predictionFixtureLockedLabel,
                    key: Key('prediction.locked.${fixture.fixtureId}'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _Tokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft, blurred circular color blob (the CSS ::before/::after color bleed).
class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// A team column: a colored circular "logo" (initials) + the team name.
class _TeamColumn extends StatelessWidget {
  const _TeamColumn({required this.name, required this.color});

  final String name;
  final Color color;

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '?') return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final first = parts.first;
      return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: _Tokens.logoSize,
          height: _Tokens.logoSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.9),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _Tokens.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The center predict area: two stepper columns (home / away) + Double pill.
class _PredictCenter extends StatelessWidget {
  const _PredictCenter({
    required this.fixtureId,
    required this.homeController,
    required this.awayController,
    required this.enabled,
    required this.isDouble,
    required this.doubleSelectable,
    required this.onDoubleSelected,
    required this.onChanged,
    required this.doubleLabel,
  });

  final String fixtureId;
  final TextEditingController homeController;
  final TextEditingController awayController;
  final bool enabled;
  final bool isDouble;
  final bool doubleSelectable;
  final VoidCallback onDoubleSelected;
  final VoidCallback onChanged;
  final String doubleLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _GoalStepper(
              key: Key('prediction.home.$fixtureId'),
              controller: homeController,
              enabled: enabled,
              onChanged: onChanged,
            ),
            const SizedBox(width: 4),
            _GoalStepper(
              key: Key('prediction.away.$fixtureId'),
              controller: awayController,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DoubleButton(
          key: Key('prediction.double.$fixtureId'),
          active: isDouble,
          enabled: doubleSelectable,
          label: doubleLabel,
          onPressed: doubleSelectable ? onDoubleSelected : null,
        ),
      ],
    );
  }
}

/// One team's +/?/− stepper column. The center shows the current goal count
/// (or "?" when empty); the field is still directly editable via a hidden tap.
class _GoalStepper extends StatelessWidget {
  const _GoalStepper({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  int get _value => int.tryParse(controller.text.trim()) ?? 0;
  bool get _hasValue => controller.text.trim().isNotEmpty;

  void _bump(int delta) {
    final next = (_value + delta).clamp(0, 99);
    controller.text = '$next';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepBtn(icon: Icons.add, enabled: enabled, onTap: () => _bump(1)),
          const SizedBox(height: 4),
          _CenterField(
            controller: controller,
            enabled: enabled,
            placeholder: _hasValue ? null : '?',
            onChanged: onChanged,
          ),
          const SizedBox(height: 4),
          _StepBtn(
            icon: Icons.remove,
            enabled: enabled,
            onTap: () => _bump(-1),
          ),
        ],
      ),
    );
  }
}

/// A single +/− button in the stepper.
class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Tokens.btnBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _Tokens.btnBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 44,
          height: 28,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? _Tokens.textSecondary : _Tokens.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// The editable center goal field (shows "?" when empty, like Fotmob).
class _CenterField extends StatelessWidget {
  const _CenterField({
    required this.controller,
    required this.enabled,
    required this.placeholder,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? placeholder;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 32,
      decoration: BoxDecoration(
        color: _Tokens.btnBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Tokens.btnBorder),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        cursorColor: _Tokens.textPrimary,
        style: const TextStyle(
          color: _Tokens.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: placeholder,
          hintStyle: const TextStyle(
            color: _Tokens.textSecondary,
            fontSize: 16,
          ),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// The neon "Double" pill under the predict controls.
class _DoubleButton extends StatelessWidget {
  const _DoubleButton({
    required this.active,
    required this.enabled,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final bool active;
  final bool enabled;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 30,
      decoration: BoxDecoration(
        color: active ? _Tokens.doubleActiveBg : _Tokens.doubleInactiveBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: active
            ? [
                BoxShadow(
                  color: _Tokens.doubleGlow.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  active ? Icons.star : Icons.star_border,
                  size: 14,
                  color: active ? _Tokens.doubleGlow : _Tokens.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? _Tokens.doubleGlow : _Tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
