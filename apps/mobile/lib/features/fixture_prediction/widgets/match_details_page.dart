library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_stroke.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/format/timestamps.dart';
import '../../../core/ui/score_pill.dart';
import '../../../core/ui/team_logo.dart';
import '../../competition/team_identity.dart';
import '../match_details_providers.dart';

/// The kinds of event the page shows; substitutions and other provider
/// notes are left out, as on Sports Mole's match page.
const Set<String> shownEventKinds = <String>{
  'goal',
  'penalty_goal',
  'own_goal',
  'missed_penalty',
  'yellow_card',
  'second_yellow',
  'red_card',
  'var_goal_cancelled',
};

/// «الجولة 8» for a provider round such as `"Regular Season - 8"`; null
/// when it carries no number.
String? roundLabel(String? round) {
  if (round == null) return null;
  final RegExpMatch? number = RegExp(r'(\d+)\s*$').firstMatch(round);
  return number == null ? null : 'الجولة ${number.group(1)}';
}

/// The story of a finished match (2026-10-19, on the model of Sports
/// Mole's match page): the sides around the final score, the half-time
/// score, the ground and the referee, then each goal and card with its
/// minute, the home side's on the home side. A goal the VAR ruled out shows
/// too, struck through. Opened from a finished match's card.
class MatchDetailsPage extends ConsumerWidget {
  const MatchDetailsPage({
    super.key,
    required this.item,
    required this.home,
    required this.away,
  });

  /// The match, with its recorded result.
  final CurrentMonthFixtureItemDto item;

  /// The home side as the card resolved it.
  final ResolvedTeamIdentity home;

  /// The away side as the card resolved it.
  final ResolvedTeamIdentity away;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String fixtureId = item.fixture.fixtureId;
    final AsyncValue<MatchDetailsDto> details = ref.watch(
      matchDetailsProvider(fixtureId),
    );
    final MatchDetailsDto? loaded = details.value;
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل المباراة')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(matchDetailsProvider(fixtureId).future),
        child: ListView(
          key: const Key('matchDetails.list'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            _Header(item: item, home: home, away: away, details: loaded),
            const SizedBox(height: AppSpacing.lg),
            switch (details) {
              AsyncData<MatchDetailsDto>(:final value) =>
                value.available
                    ? _Timeline(events: value.events)
                    : const _Notice(
                        key: Key('matchDetails.notYet'),
                        message:
                            'لم تصل أحداث هذه المباراة بعد. تُجلب بعد '
                            'نهايتها بقليل، فاسحب الصفحة للأسفل لاحقاً.',
                      ),
              AsyncError<MatchDetailsDto>(:final error) => _Notice(
                key: const Key('matchDetails.error'),
                message: ErrorPresenter.messageOf(error),
                onRetry: () => ref.invalidate(matchDetailsProvider(fixtureId)),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// The two sides around the final score, then the half-time score, the
/// round, the ground and the referee once the details are in.
class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.home,
    required this.away,
    required this.details,
  });

  final CurrentMonthFixtureItemDto item;
  final ResolvedTeamIdentity home;
  final ResolvedTeamIdentity away;
  final MatchDetailsDto? details;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final SeasonFixtureCardDto fixture = item.fixture;
    final int? homeGoals = item.resultHomeGoals;
    final int? awayGoals = item.resultAwayGoals;
    final MatchDetailsDto? story = details;
    final int? htHome = story?.halfTimeHome;
    final int? htAway = story?.halfTimeAway;
    final String? round = roundLabel(story?.round);
    final String league = fixture.leagueName ?? item.competitionName;
    final String? kickoff = fixture.kickoffAt;
    final TextStyle muted = TextStyle(
      fontSize: AppFontSize.s12,
      color: tokens.textSecondary,
    );
    return Container(
      key: const Key('matchDetails.header'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: tokens.border, width: AppStroke.hairline),
      ),
      child: Column(
        children: <Widget>[
          Text(
            round == null ? league : '$league · $round',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.s14,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          if (kickoff != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              formatTimestamp(context, kickoff),
              textAlign: TextAlign.center,
              style: muted,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _SidesAndScore(
            home: _Side(team: home),
            away: _Side(team: away),
            score: Column(
              children: <Widget>[
                Text(
                  homeGoals != null && awayGoals != null
                      ? orientedScoreLabel(context, homeGoals, awayGoals)
                      : '-',
                  key: const Key('matchDetails.score'),
                  // Two digit runs around a neutral dash: left to the Arabic paragraph
                  // they swap places: Brighton 5-0 Crystal Palace drew Brighton's 5
                  // under Palace's crest (2026-10-19).
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: AppFontSize.s26,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                if (htHome != null && htAway != null)
                  Row(
                    key: const Key('matchDetails.halfTime'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(child: Text('الشوط الأول:', style: muted)),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        orientedScoreLabel(context, htHome, htAway),
                        key: const Key('matchDetails.halfTimeScore'),
                        textDirection: TextDirection.ltr,
                        style: muted,
                      ),
                    ],
                  ),
                Text('انتهت', style: muted),
              ],
            ),
          ),
          if (story != null && story.venue != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _InfoLine(
              key: const Key('matchDetails.venue'),
              icon: Icons.stadium_outlined,
              text: story.venue!,
            ),
          ],
          if (story != null && story.referee != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _InfoLine(
              icon: Icons.sports_outlined,
              text: 'الحكم: ${story.referee!}',
            ),
          ],
        ],
      ),
    );
  }
}

/// The two sides with the score between them; on a narrow screen or at a
/// large text size, which left no room for the score on 2026-10-19 (360px,
/// text x2), the score goes under the sides.
class _SidesAndScore extends StatelessWidget {
  const _SidesAndScore({
    required this.home,
    required this.away,
    required this.score,
  });

  final Widget home;
  final Widget away;
  final Widget score;

  /// Width, at text x1, below which the score goes under the sides.
  static const double _inlineWidth = 260;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth / scale >= _inlineWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 2, child: home),
              Expanded(flex: 3, child: score),
              Expanded(flex: 2, child: away),
            ],
          );
        }
        return Column(
          key: const Key('matchDetails.stacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: home),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: away),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            score,
          ],
        );
      },
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.team});

  final ResolvedTeamIdentity team;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      children: <Widget>[
        TeamLogo(
          displayName: team.displayName,
          crestUrl: team.crestUrl,
          assetPath: team.assetPath,
          brandColor: team.brandColor,
          size: 44,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          team.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppFontSize.s13,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 16, color: tokens.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.s12,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Each goal and card in the provider's order, the home side's on the
/// home side, the minute between.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<MatchEventDto> events;

  @override
  Widget build(BuildContext context) {
    final List<MatchEventDto> shown = <MatchEventDto>[
      for (final MatchEventDto event in events)
        if (shownEventKinds.contains(event.kind)) event,
    ];
    if (shown.isEmpty) {
      return const _Notice(
        key: Key('matchDetails.quiet'),
        message: 'لا أهداف ولا بطاقات في هذه المباراة.',
      );
    }
    return Column(
      key: const Key('matchDetails.timeline'),
      children: <Widget>[
        for (int i = 0; i < shown.length; i++)
          _EventRow(key: Key('matchDetails.event.$i'), event: shown[i]),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({super.key, required this.event});

  final MatchEventDto event;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Widget cell = _EventCell(event: event);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: event.home
                ? Align(alignment: AlignmentDirectional.centerEnd, child: cell)
                : const SizedBox.shrink(),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 52),
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: AppRadius.brButton,
            ),
            child: Text(
              "${event.minute}'",
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: AppFontSize.s12,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: event.home
                ? const SizedBox.shrink()
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: cell,
                  ),
          ),
        ],
      ),
    );
  }
}

/// One event: its mark, the player, and a second line saying what kind of
/// goal or card it was when that is not plain.
class _EventCell extends StatelessWidget {
  const _EventCell({required this.event});

  final MatchEventDto event;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bool cancelled = event.kind == 'var_goal_cancelled';
    final String? note = switch (event.kind) {
      'penalty_goal' => 'ركلة جزاء',
      'own_goal' => 'في مرماه',
      'missed_penalty' => 'ركلة جزاء ضائعة',
      'second_yellow' => 'إنذار ثانٍ',
      'var_goal_cancelled' => 'هدف ألغاه حكم الفيديو (VAR)',
      'goal' => event.assist == null ? null : 'صناعة: ${event.assist}',
      _ => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Mark(kind: event.kind),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.player ?? '—',
                style: TextStyle(
                  fontSize: AppFontSize.s13,
                  fontWeight: FontWeight.w600,
                  color: cancelled ? tokens.textMuted : tokens.textPrimary,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              if (note != null)
                Text(
                  note,
                  style: TextStyle(
                    fontSize: AppFontSize.s11,
                    color: tokens.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A goal's ball, a card's colour, the VAR's cross.
class _Mark extends StatelessWidget {
  const _Mark({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget card(Color color) => Container(
      width: 11,
      height: 15,
      margin: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return switch (kind) {
      'yellow_card' => card(const Color(0xFFF5C518)),
      'red_card' => card(tokens.error),
      'second_yellow' => card(tokens.error),
      'var_goal_cancelled' => Icon(
        Icons.block_rounded,
        size: 18,
        color: tokens.textMuted,
      ),
      'missed_penalty' => Icon(
        Icons.close_rounded,
        size: 18,
        color: tokens.textMuted,
      ),
      'own_goal' => Icon(
        Icons.sports_soccer_rounded,
        size: 18,
        color: tokens.error,
      ),
      _ => Icon(
        Icons.sports_soccer_rounded,
        size: 18,
        color: tokens.textPrimary,
      ),
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: <Widget>[
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.s13,
              color: tokens.textSecondary,
            ),
          ),
          if (onRetry != null)
            TextButton.icon(
              key: const Key('matchDetails.retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
        ],
      ),
    );
  }
}
