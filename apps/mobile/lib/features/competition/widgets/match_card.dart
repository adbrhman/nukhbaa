// apps/mobile/lib/features/competition/widgets/match_card.dart
//
// Nukhba — Premium match card (Elite Obsidian V1.0).
//
// Consumes only symbols verified to exist in this repo (2026-09-04).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/branding/team_branding.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';

enum MatchStatus { scheduled, live, finished, postponed }

class MatchCardData {
  const MatchCardData({
    required this.fixtureId,
    required this.competitionName,
    required this.seasonLabel,
    required this.kickoff,
    required this.status,
    required this.homeTeamName,
    required this.awayTeamName,
    this.homeTeamLogoPath,
    this.awayTeamLogoPath,
    this.homeScore,
    this.awayScore,
    this.homePenalty,
    this.awayPenalty,
    this.liveMinute,
    this.homeWinProbability,
    this.drawProbability,
    this.awayWinProbability,
    this.predictedHomeGoals,
    this.predictedAwayGoals,
    this.isDouble = false,
    this.hasUserPrediction = false,
    this.onTap,
    this.onPredictTap,
  });

  final String fixtureId;
  final String competitionName;
  final String seasonLabel;
  final DateTime kickoff;
  final MatchStatus status;
  final String homeTeamName;
  final String awayTeamName;
  final String? homeTeamLogoPath;
  final String? awayTeamLogoPath;
  final int? homeScore;
  final int? awayScore;
  final int? homePenalty;
  final int? awayPenalty;
  final int? liveMinute;
  final double? homeWinProbability;
  final double? drawProbability;
  final double? awayWinProbability;
  final int? predictedHomeGoals;
  final int? predictedAwayGoals;
  final bool isDouble;
  final bool hasUserPrediction;
  final VoidCallback? onTap;
  final VoidCallback? onPredictTap;
}

class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.data});

  final MatchCardData data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);

    return Semantics(
      label: l.fixtureVsTitle(data.homeTeamName, data.awayTeamName),
      button: data.onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.brXl,
          onTap: data.onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: AppRadius.brXl,
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  t.surfaceElevated,
                  Color.lerp(t.surfaceElevated, t.primary, 0.06)!,
                ],
              ),
              border: Border.all(color: t.border),
              boxShadow: t.shadowMd,
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.brXl,
                      gradient: RadialGradient(
                        center: const Alignment(0, -1.4),
                        radius: 1.6,
                        colors: <Color>[
                          t.primary.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _CompetitionRow(data: data),
                      const SizedBox(height: AppSpacing.md),
                      _TeamsRow(data: data),
                      if (data.status == MatchStatus.scheduled) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        _KickoffCountdown(kickoff: data.kickoff),
                      ],
                      if (data.homeWinProbability != null &&
                          data.awayWinProbability != null &&
                          data.status != MatchStatus.scheduled) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        _ProbabilityBar(data: data),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _Footer(data: data),
                    ],
                  ),
                ),
                if (data.isDouble)
                  Positioned(
                    top: AppSpacing.md,
                    left: context.isRtl ? null : AppSpacing.md,
                    right: context.isRtl ? AppSpacing.md : null,
                    child: const _DoubleBadge(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompetitionRow extends StatelessWidget {
  const _CompetitionRow({required this.data});

  final MatchCardData data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;
    final l = AppLocalizations.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: t.primaryGradient,
            borderRadius: AppRadius.brSm,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: t.primary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.emoji_events_outlined,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(data.competitionName, style: txt.titleSmall),
              const SizedBox(height: 2),
              Text(
                '${l.matchesTitle} · ${data.seasonLabel}',
                style: txt.bodySmall?.copyWith(color: t.textMuted),
              ),
            ],
          ),
        ),
        _StatusBadge(status: data.status),
      ],
    );
  }
}

class _TeamsRow extends StatelessWidget {
  const _TeamsRow({required this.data});

  final MatchCardData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: _TeamColumn(
            name: data.homeTeamName,
            shortName: data.homeTeamName,
            logoPath: data.homeTeamLogoPath,
            alignEnd: false,
          ),
        ),
        _ScoreColumn(data: data),
        Expanded(
          child: _TeamColumn(
            name: data.awayTeamName,
            shortName: data.awayTeamName,
            logoPath: data.awayTeamLogoPath,
            alignEnd: true,
          ),
        ),
      ],
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.name,
    required this.shortName,
    required this.logoPath,
    required this.alignEnd,
  });

  final String name;
  final String shortName;
  final String? logoPath;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: <Widget>[
        _TeamCrest(name: name, logoPath: logoPath),
        const SizedBox(height: AppSpacing.sm),
        Text(
          shortName,
          style: txt.titleMedium,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          teamInitials(name),
          style: txt.bodySmall?.copyWith(color: t.textMuted),
          textDirection: TextDirection.ltr,
        ),
      ],
    );
  }
}

class _TeamCrest extends StatelessWidget {
  const _TeamCrest({required this.name, required this.logoPath});

  final String name;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final b = brandingForTeam(name);
    final initials = teamInitials(name);

    final Widget inside = logoPath != null && logoPath!.isNotEmpty
        ? Image.asset(
            logoPath!,
            width: 64,
            height: 64,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Text(
              initials,
              style: TextStyle(
                color: t.onPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          )
        : Text(
            initials,
            style: TextStyle(
              color: t.onPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          );

    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.6),
          radius: 1.1,
          colors: <Color>[b.secondary, b.primary],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 3,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: b.primary.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: inside),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({required this.data});

  final MatchCardData data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;
    final l = AppLocalizations.of(context);
    final live = data.status == MatchStatus.live;
    final finished = data.status == MatchStatus.finished;
    final scheduled = data.status == MatchStatus.scheduled;
    final locked = live || finished;
    final hasScore = data.homeScore != null || data.awayScore != null;

    return SizedBox(
      width: 116,
      child: Column(
        children: <Widget>[
          if (live)
            _LiveBadge(minute: data.liveMinute ?? 0)
          else if (finished)
            _StatusPill(
              label: l.predictionFixtureLockedLabel,
              kind: _PillKind.finished,
            )
          else if (data.status == MatchStatus.postponed)
            // NO ARB key yet.
            const _StatusPill(label: 'مؤجلة', kind: _PillKind.finished)
          else
            // NO ARB key yet.
            const _StatusPill(label: 'لم تبدأ', kind: _PillKind.upcoming),
          const SizedBox(height: AppSpacing.sm),
          Text(
            locked
                ? (hasScore
                    ? '${data.homeScore ?? 0} – ${data.awayScore ?? 0}'
                    : '— : —')
                : '— : —',
            textDirection: TextDirection.ltr,
            style: txt.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: scheduled ? t.textMuted : t.textPrimary,
            ),
          ),
          if (finished &&
              (data.homePenalty != null || data.awayPenalty != null)) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: t.gold.withValues(alpha: 0.14),
                border: Border.all(color: t.gold.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                // NO ARB key yet.
                'ركلات الترجيح  ${data.homePenalty ?? 0} – ${data.awayPenalty ?? 0}',
                textDirection: TextDirection.rtl,
                style: txt.labelSmall?.copyWith(
                  color: t.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProbabilityBar extends StatelessWidget {
  const _ProbabilityBar({required this.data});

  final MatchCardData data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;
    final h = ((data.homeWinProbability ?? 0) * 100).clamp(0, 100);
    final d = ((data.drawProbability ?? 0) * 100).clamp(0, 100);
    final a = ((data.awayWinProbability ?? 0) * 100).clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('${h.toInt()}%', style: txt.labelSmall?.copyWith(color: t.error)),
            const Spacer(),
            Text(
              '${d.toInt()}%',
              style: txt.labelSmall?.copyWith(color: t.textMuted),
            ),
            const Spacer(),
            Text('${a.toInt()}%', style: txt.labelSmall?.copyWith(color: t.gold)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 6,
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: h.round().clamp(1, 100),
                  child: Container(color: t.error.withValues(alpha: 0.85)),
                ),
                Expanded(
                  flex: d.round().clamp(1, 100),
                  child: Container(color: t.textMuted.withValues(alpha: 0.6)),
                ),
                Expanded(
                  flex: a.round().clamp(1, 100),
                  child: Container(color: t.gold.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KickoffCountdown extends StatefulWidget {
  const _KickoffCountdown({required this.kickoff});

  final DateTime kickoff;

  @override
  State<_KickoffCountdown> createState() => _KickoffCountdownState();
}

class _KickoffCountdownState extends State<_KickoffCountdown> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;
    final l = AppLocalizations.of(context);
    final left = widget.kickoff.difference(_now);
    if (left.isNegative) return const SizedBox.shrink();

    String two(int n) => n.toString().padLeft(2, '0');
    final d = left.inDays;
    final h = left.inHours.remainder(24);
    final m = left.inMinutes.remainder(60);
    final s = left.inSeconds.remainder(60);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _seg(two(h), txt, t),
        _sep(txt, t),
        _seg(two(m), txt, t),
        _sep(txt, t),
        _seg(two(s), txt, t),
        if (d > 0) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          Text(
            l.kickoffCountdownDays(d),
            style: txt.bodySmall?.copyWith(color: t.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _seg(String s, TextTheme txt, AppTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: t.surfaceHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border),
        ),
        child: Text(
          s,
          textDirection: TextDirection.ltr,
          style: txt.titleMedium?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      );

  Widget _sep(TextTheme txt, AppTokens t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          ':',
          style: txt.titleMedium?.copyWith(color: t.textMuted),
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.data});

  final MatchCardData data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;
    final l = AppLocalizations.of(context);

    final canPredict =
        data.status == MatchStatus.scheduled && !data.hasUserPrediction;
    final wasPredicted = data.hasUserPrediction;
    final live = data.status == MatchStatus.live;
    final finished = data.status == MatchStatus.finished;

    final cta = FilledButton.icon(
      onPressed: canPredict ? data.onPredictTap : null,
      icon: Icon(
        canPredict
            ? Icons.sports_soccer
            : (wasPredicted ? Icons.check_circle : Icons.lock_outline),
        size: 18,
      ),
      label: Text(
        canPredict
            ? l.submitPredictionButton
            : (wasPredicted
                ? l.predictionYourForecastScoreLine(
                    data.predictedHomeGoals ?? 0,
                    data.predictedAwayGoals ?? 0,
                  )
                : l.predictionFixtureLockedLabel),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: canPredict ? t.primary : t.surfaceHigh,
        foregroundColor: canPredict ? t.onPrimary : t.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        shape: const StadiumBorder(),
        textStyle: txt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (live)
                Row(
                  children: <Widget>[
                    Icon(Icons.circle, color: t.error, size: 8),
                    const SizedBox(width: 6),
                    // NO ARB key yet.
                    Text(
                      'مباشر الآن',
                      style: txt.labelSmall?.copyWith(
                        color: t.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              else if (finished)
                Text(
                  l.predictionFixtureLockedLabel,
                  style: txt.labelSmall?.copyWith(
                    color: t.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else if (wasPredicted)
                Text(
                  l.predictionYourForecastScoreLine(
                    data.predictedHomeGoals ?? 0,
                    data.predictedAwayGoals ?? 0,
                  ),
                  style: txt.labelSmall?.copyWith(
                    color: t.gold,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                // NO ARB key yet.
                Text(
                  'اضغط لتوقّع النتيجة',
                  style: txt.bodySmall?.copyWith(color: t.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: cta),
      ],
    );
  }
}

enum _PillKind { live, finished, upcoming }

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final MatchStatus status;

  @override
  Widget build(BuildContext context) {
    final (_PillKind kind, String label) = switch (status) {
      // These have NO ARB keys yet.
      MatchStatus.live => (_PillKind.live, 'مباشر'),
      MatchStatus.finished => (_PillKind.finished, 'انتهت'),
      MatchStatus.postponed => (_PillKind.finished, 'مؤجلة'),
      MatchStatus.scheduled => (_PillKind.upcoming, 'قادمة'),
    };
    return _StatusPill(label: label, kind: kind);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.kind});

  final String label;
  final _PillKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;
    final colors = switch (kind) {
      _PillKind.live => (
          t.error.withValues(alpha: 0.14),
          t.error,
          t.error.withValues(alpha: 0.4),
        ),
      _PillKind.finished => (t.surfaceHigh, t.textSecondary, t.border),
      _PillKind.upcoming => (
          t.gold.withValues(alpha: 0.14),
          t.gold,
          t.gold.withValues(alpha: 0.4),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.$3),
      ),
      child: Text(
        label,
        style: txt.labelSmall?.copyWith(
          color: colors.$2,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.minute});

  final int minute;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.error.withValues(alpha: 0.14),
        border: Border.all(color: t.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.error,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: t.error.withValues(alpha: 0.6 * (1 - _c.value)),
                    blurRadius: 6 + 6 * _c.value,
                    spreadRadius: 1 + 2 * _c.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // NO ARB key yet.
          Text(
            'الدقيقة  ${widget.minute}',
            textDirection: TextDirection.ltr,
            style: txt.labelSmall?.copyWith(
              color: t.error,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubleBadge extends StatelessWidget {
  const _DoubleBadge();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final txt = context.text;
    final l = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: t.goldGradient,
        borderRadius: BorderRadius.circular(8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: t.gold.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            l.predictionDoubleLabel,
            style: txt.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
