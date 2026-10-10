/// The first section of a seated month: the match that matters now -- the
/// round being played, else the next one with the time left to its first
/// kickoff, else the last one played.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_button.dart';
import '../../../core/ui/app_card.dart';
import '../h2h_round_screen.dart';
import '../h2h_texts.dart';
import 'h2h_parts.dart';

/// The match that matters now, or why there is none yet.
class H2hNextMatch extends StatelessWidget {
  /// Creates the section for [league].
  const H2hNextMatch({
    required this.league,
    required this.now,
    this.onOpenMatches,
    super.key,
  });

  /// The month as the server sent it.
  final MyH2hLeagueDto league;

  /// The device clock, for the countdown only; every state is the server's.
  final DateTime Function() now;

  /// Opens the matches tab, where the round's fixtures are predicted. Null
  /// hides the button.
  final VoidCallback? onOpenMatches;

  @override
  Widget build(BuildContext context) {
    final H2hRoundViewDto? round = h2hCurrentRound(league);
    if (round == null) return const H2hNoRounds();
    final AppTokens t = context.tokens;
    final H2hStandingDto? me = h2hMyStanding(league);
    final bool live = round.status == 'live';
    final bool ahead = round.status == 'open' || round.status == 'upcoming';
    final String heading = switch (round.status) {
      'live' => 'مواجهة اليوم · جارية',
      'open' || 'upcoming' => 'المواجهة القادمة · ${h2hDayLabel(round.day)}',
      _ => 'آخر مواجهة · ${h2hDayLabel(round.day)}',
    };
    final DateTime? kickoff = round.firstKickoff == null
        ? null
        : DateTime.tryParse(round.firstKickoff!)?.toUtc();
    final TextStyle? scoreStyle = context.text.headlineSmall?.copyWith(
      color: t.textPrimary,
      fontWeight: FontWeight.w800,
    );
    final Widget middle;
    if (round.myPoints != null) {
      middle = Wrap(
        key: const Key('h2h.featured.score'),
        alignment: WrapAlignment.center,
        children: <Widget>[
          Text(
            h2hPointsLabel(round.myPoints!),
            key: const Key('h2h.featured.mine'),
            style: scoreStyle,
          ),
          Text(' - ', style: scoreStyle),
          Text(
            h2hPointsLabel(round.opponentPoints ?? 0),
            key: const Key('h2h.featured.theirs'),
            style: scoreStyle,
          ),
        ],
      );
    } else if (ahead && kickoff != null) {
      middle = H2hCountdown(kickoff: kickoff, now: now);
    } else {
      middle = Text(
        'ضد',
        style: context.text.titleSmall?.copyWith(color: t.textSecondary),
      );
    }
    return AppCard(
      key: const Key('h2h.featured'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'الجولة ${round.round} · $heading',
            key: const Key('h2h.featured.heading'),
            style: context.text.labelLarge?.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: H2hSide(
                  name: h2hNameOf(me?.displayName),
                  avatarUrl: me?.avatarUrl,
                  average: false,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Center(child: middle),
                ),
              ),
              Expanded(
                child: H2hSide(
                  name: h2hOpponentOf(round),
                  avatarUrl: round.opponentAvatarUrl,
                  average: round.opponentUserId == null,
                ),
              ),
            ],
          ),
          if (round.result != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: H2hResultBadge(result: round.result!, live: live),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'مباريات الجولة: ${round.fixtureCount}',
            key: const Key('h2h.featured.fixtures'),
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const Key('h2h.openRound'),
            label: 'تفاصيل المواجهة',
            icon: Icons.list_alt_rounded,
            variant: AppButtonVariant.text,
            size: AppButtonSize.large,
            onPressed: () => openH2hRound(context, round.round),
          ),
          if (onOpenMatches != null && (ahead || live)) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('h2h.goToMatches'),
              label: 'اذهب إلى المباريات',
              icon: Icons.sports_soccer_rounded,
              variant: AppButtonVariant.secondary,
              // A full touch target (48 and up).
              size: AppButtonSize.large,
              onPressed: onOpenMatches,
            ),
          ],
        ],
      ),
    );
  }
}

/// The time left until a round's first kickoff, in hours and minutes,
/// redrawn once a minute.
///
/// PERF: the tab stays mounted in the shell's IndexedStack. Out of sight
/// (the shell turns its tickers off) or with the app in the background, the
/// timer stops, and it resynchronises when the tab is seen again.
class H2hCountdown extends StatefulWidget {
  /// Creates a countdown to [kickoff] (UTC) on the [now] clock.
  const H2hCountdown({required this.kickoff, required this.now, super.key});

  /// The first kickoff of the round, UTC.
  final DateTime kickoff;

  /// The clock the countdown reads.
  final DateTime Function() now;

  @override
  State<H2hCountdown> createState() => _H2hCountdownState();
}

class _H2hCountdownState extends State<H2hCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = true;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant H2hCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kickoff != widget.kickoff) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _schedule();
    if (_resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Duration get _left => widget.kickoff.difference(widget.now().toUtc());

  /// One shot to just past the next whole minute of what is left (where
  /// the label changes), while seen.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final Duration left = _left;
    if (!_visible || !_resumed || left <= Duration.zero) return;
    final int intoMinute = left.inMicroseconds % Duration.microsecondsPerMinute;
    final Duration wait = Duration(
      microseconds:
          (intoMinute == 0 ? Duration.microsecondsPerMinute : intoMinute) +
          Duration.microsecondsPerMillisecond,
    );
    _timer = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Duration left = _left;
    final String label = h2hCountdownLabel(left);
    return Semantics(
      label: left <= Duration.zero ? label : 'تبدأ بعد $label',
      excludeSemantics: true,
      child: Column(
        key: const Key('h2h.countdown'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (left > Duration.zero)
            Text(
              'تبدأ بعد',
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(color: t.textSecondary),
            ),
          Text(
            label,
            key: const Key('h2h.countdown.value'),
            textAlign: TextAlign.center,
            style: context.text.titleMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The month holds no round to show yet.
class H2hNoRounds extends StatelessWidget {
  /// Creates the note.
  const H2hNoRounds({super.key});

  @override
  Widget build(BuildContext context) => AppCard(
    key: const Key('h2h.noRounds'),
    child: Text(
      'لم تُعتمد أي جولة بعد. $h2hRoundsNote',
      style: context.text.bodyMedium?.copyWith(
        color: context.tokens.textSecondary,
      ),
    ),
  );
}
