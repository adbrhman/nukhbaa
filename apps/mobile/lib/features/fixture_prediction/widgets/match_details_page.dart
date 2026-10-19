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

/// What follows a player's name when the mark alone does not say it.
String? eventNote(String kind) => switch (kind) {
  'penalty_goal' => '(ج)',
  'own_goal' => '(في مرماه)',
  'missed_penalty' => '(ج ضائعة)',
  'second_yellow' => '(إنذار ثانٍ)',
  'var_goal_cancelled' => '(ألغاه الفيديو)',
  _ => null,
};

/// The story of a finished match, laid out like Sports Mole's match page
/// (2026-10-19): one card with the league and round, the date, the sides
/// around the final score, the half-time score, «انتهت» and the ground, and
/// under them each side's goals and cards in its own column, under its own
/// crest. A goal the VAR ruled out shows too, struck through. Opened from a
/// finished match's card.
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
    final List<MatchEventDto> shown = <MatchEventDto>[
      if (loaded != null && loaded.available)
        for (final MatchEventDto event in loaded.events)
          if (shownEventKinds.contains(event.kind)) event,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل المباراة')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(matchDetailsProvider(fixtureId).future),
        child: ListView(
          key: const Key('matchDetails.list'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            _Header(
              item: item,
              home: home,
              away: away,
              details: loaded,
              events: shown,
            ),
            switch (details) {
              AsyncData<MatchDetailsDto>(:final value) =>
                !value.available
                    ? const _Notice(
                        key: Key('matchDetails.notYet'),
                        message:
                            'لم تصل أحداث هذه المباراة بعد. تُجلب بعد '
                            'نهايتها بقليل، فاسحب الصفحة للأسفل لاحقاً.',
                      )
                    : shown.isEmpty
                    ? const _Notice(
                        key: Key('matchDetails.quiet'),
                        message: 'لا أهداف ولا بطاقات في هذه المباراة.',
                      )
                    : const SizedBox.shrink(),
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

/// The one card of the page: the sides around the final score, the
/// half-time score, the ground, then the two columns of [events].
class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.home,
    required this.away,
    required this.details,
    required this.events,
  });

  final CurrentMonthFixtureItemDto item;
  final ResolvedTeamIdentity home;
  final ResolvedTeamIdentity away;
  final MatchDetailsDto? details;
  final List<MatchEventDto> events;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            league,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.s14,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          if (round != null)
            Text(
              round,
              key: const Key('matchDetails.round'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.s12,
                fontWeight: FontWeight.w600,
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
                  // Two digit runs around a neutral dash: left to the Arabic
                  // paragraph they swap places: Brighton 5-0 Crystal Palace
                  // drew Brighton's 5 under Palace's crest (2026-10-19).
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
                if (story != null && story.venue != null)
                  Text(
                    story.venue!,
                    key: const Key('matchDetails.venue'),
                    textAlign: TextAlign.center,
                    style: muted,
                  ),
              ],
            ),
          ),
          if (events.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: tokens.border),
            const SizedBox(height: AppSpacing.md),
            _EventColumns(events: events, home: home, away: away),
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

/// Each side's goals and cards in its own column, in the provider's order:
/// the home side's under the home crest, each line's mark towards the
/// middle, as on Sports Mole. When two columns do not fit (a narrow screen,
/// a large text size) the away side's list goes under the home side's, each
/// under the side's name.
class _EventColumns extends StatelessWidget {
  const _EventColumns({
    required this.events,
    required this.home,
    required this.away,
  });

  final List<MatchEventDto> events;
  final ResolvedTeamIdentity home;
  final ResolvedTeamIdentity away;

  /// Width, at text x1, below which the two lists go one under the other.
  static const double _sideBySideWidth = 220;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    List<Widget> linesOf({required bool homeSide}) => <Widget>[
      for (int i = 0; i < events.length; i++)
        if (events[i].home == homeSide)
          _EventLine(
            key: Key('matchDetails.event.$i'),
            event: events[i],
            towardsMiddle: homeSide,
          ),
    ];
    final Widget homeList = Column(
      key: const Key('matchDetails.homeEvents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: linesOf(homeSide: true),
    );
    final Widget awayList = Column(
      key: const Key('matchDetails.awayEvents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: linesOf(homeSide: false),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth / scale >= _sideBySideWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: homeList),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: awayList),
            ],
          );
        }
        return Column(
          key: const Key('matchDetails.eventsStacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ListTitle(name: home.displayName),
            homeList,
            const SizedBox(height: AppSpacing.md),
            _ListTitle(name: away.displayName),
            awayList,
          ],
        );
      },
    );
  }
}

class _ListTitle extends StatelessWidget {
  const _ListTitle({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        name,
        style: TextStyle(
          fontSize: AppFontSize.s12,
          fontWeight: FontWeight.w700,
          color: context.tokens.textSecondary,
        ),
      ),
    );
  }
}

/// One goal or card: the player, the minute and the mark. The home side's
/// lines (on the right in Arabic) end with the mark towards the middle; the
/// away side's start with it.
class _EventLine extends StatelessWidget {
  const _EventLine({
    super.key,
    required this.event,
    required this.towardsMiddle,
  });

  final MatchEventDto event;

  /// Whether the line is packed towards the middle, mark last: the home
  /// side's.
  final bool towardsMiddle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bool cancelled = event.kind == 'var_goal_cancelled';
    final String? note = eventNote(event.kind);
    final Widget name = Flexible(
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: event.player ?? '—',
              style: TextStyle(
                color: cancelled ? tokens.textMuted : tokens.textPrimary,
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
            if (note != null)
              TextSpan(
                text: ' $note',
                style: TextStyle(color: tokens.textSecondary),
              ),
          ],
        ),
        textAlign: towardsMiddle ? TextAlign.end : TextAlign.start,
        style: const TextStyle(
          fontSize: AppFontSize.s13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final Widget minute = Text(
      "${event.minute}'",
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontSize: AppFontSize.s12,
        fontWeight: FontWeight.w700,
        color: tokens.textSecondary,
      ),
    );
    const Widget gap = SizedBox(width: AppSpacing.xs);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: towardsMiddle
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: towardsMiddle
            ? <Widget>[name, gap, minute, gap, _Mark(kind: event.kind)]
            : <Widget>[_Mark(kind: event.kind), gap, name, gap, minute],
      ),
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
