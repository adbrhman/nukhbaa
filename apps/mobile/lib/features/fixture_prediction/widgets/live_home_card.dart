/// The home page's live card: while a match the viewer predicted is in
/// play, what their prediction would earn if it ended now, their place on
/// the month board now and then, and who leads each of their duels on it.
/// Hidden when nothing they predicted is in play. Everything is graded on
/// the server (`GET /seasons/{id}/live`); nothing here is stored.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../competition/team_catalog_index.dart';
import '../../competition/team_identity.dart';
import '../../history/prediction_lookup_providers.dart';
import '../current_month_fixtures_providers.dart';
import '../live_standing_providers.dart';
import 'live_matches_chip.dart';

/// The card; renders nothing while loading, on error, or with nothing in
/// play.
class LiveHomeCard extends ConsumerWidget {
  /// Creates the card; [onOpenMatches] opens the matches tab.
  const LiveHomeCard({required this.onOpenMatches, super.key});

  /// Opens the matches tab.
  final VoidCallback onOpenMatches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<CurrentMonthFixtureItemDto> feed =
        ref.watch(currentMonthFixturesProvider).value ??
        const <CurrentMonthFixtureItemDto>[];
    final Map<String, FixturePredictionDto> mine =
        ref.watch(myFixturePredictionsByFixtureProvider).value ??
        const <String, FixturePredictionDto>{};
    final Map<String, CurrentMonthFixtureItemDto> playing =
        <String, CurrentMonthFixtureItemDto>{
          for (final CurrentMonthFixtureItemDto item in feed)
            if (mine.containsKey(item.fixture.fixtureId) &&
                (item.liveHomeGoals != null ||
                    isFixtureLive(item.fixture.kickoffAt)))
              item.fixture.fixtureId: item,
        };
    if (playing.isEmpty) return const SizedBox.shrink();

    final List<(String, LiveStandingDto)> standings =
        <(String, LiveStandingDto)>[
          for (final String seasonId in <String>{
            for (final CurrentMonthFixtureItemDto item in playing.values)
              item.fixture.seasonId,
          })
            if (ref.watch(liveStandingProvider(seasonId)).value
                case final LiveStandingDto standing)
              (seasonId, standing),
        ];
    // A match shows once, with the duels of the season that reported it.
    final Set<String> shown = <String>{};
    final List<
      (CurrentMonthFixtureItemDto, LiveFixtureStandingDto, LiveStandingDto)
    >
    lines =
        <(CurrentMonthFixtureItemDto, LiveFixtureStandingDto, LiveStandingDto)>[
          for (final (String _, LiveStandingDto s) in standings)
            for (final LiveFixtureStandingDto f in s.fixtures)
              if (playing[f.fixtureId]
                  case final CurrentMonthFixtureItemDto item
                  when f.myPoints != null && shown.add(f.fixtureId))
                (item, f, s),
        ];
    if (lines.isEmpty) return const SizedBox.shrink();

    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final Map<String, TeamDto>? catalogById = ref.watch(
      teamCatalogByIdProvider,
    );
    final TextStyle? line = text.bodyMedium?.copyWith(
      color: tokens.textSecondary,
    );
    String team(String? id, String? name) => resolveTeamIdentity(
      catalog: null,
      catalogById: catalogById,
      teamId: id,
      teamName: name,
    ).displayName;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: tokens.surface,
        borderRadius: AppRadius.brCard,
        child: InkWell(
          key: const Key('home.live'),
          onTap: onOpenMatches,
          borderRadius: AppRadius.brCard,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: AppRadius.brCard,
              border: Border.all(color: tokens.error.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: tokens.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'مباشر الآن',
                      style: text.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                for (final (
                      CurrentMonthFixtureItemDto item,
                      LiveFixtureStandingDto f,
                      LiveStandingDto s,
                    )
                    in lines) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${team(item.fixture.homeTeamId, item.fixture.homeTeam)} '
                    '${f.homeGoals} - ${f.awayGoals} '
                    '${team(item.fixture.awayTeamId, item.fixture.awayTeam)}'
                    '${liveClock(f)}',
                    key: Key('home.live.score.${f.fixtureId}'),
                    style: text.titleSmall?.copyWith(color: tokens.textPrimary),
                  ),
                  Text(
                    'توقعك ${mine[f.fixtureId]!.homeGoals} - '
                    '${mine[f.fixtureId]!.awayGoals}، '
                    'ونقاطك لو انتهت الآن: ${f.myPoints}',
                    key: Key('home.live.points.${f.fixtureId}'),
                    style: line,
                  ),
                  for (final (int n, LiveDuelStandingDto d)
                      in <LiveDuelStandingDto>[
                        for (final LiveDuelStandingDto x in s.duels)
                          if (x.fixtureId == f.fixtureId) x,
                      ].indexed)
                    Text(
                      liveDuelLine(d),
                      key: Key('home.live.duel.${f.fixtureId}.$n'),
                      style: line,
                    ),
                ],
                for (final (String seasonId, LiveStandingDto s) in standings)
                  if (s.rankIfEnded != null &&
                      s.fixtures.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      liveRankLine(s),
                      key: Key('home.live.rank.$seasonId'),
                      style: text.bodyMedium?.copyWith(
                        color: tokens.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The minute after the score, or that the match is over.
String liveClock(LiveFixtureStandingDto f) {
  if (f.finished) return ' · انتهت';
  final int? minute = f.minute;
  return minute == null ? '' : ' · الدقيقة $minute';
}

/// Who leads a duel if the match ended now.
String liveDuelLine(LiveDuelStandingDto d) {
  final String score = '${d.myPoints} - ${d.opponentPoints}';
  if (d.myPoints > d.opponentPoints) {
    return 'تتقدم على ${d.opponentName} في المواجهة ($score)';
  }
  if (d.myPoints < d.opponentPoints) {
    return '${d.opponentName} يتقدم عليك في المواجهة ($score)';
  }
  return 'مواجهتك مع ${d.opponentName} متعادلة ($score)';
}

/// The month place now and if the matches in play ended now.
String liveRankLine(LiveStandingDto s) {
  final int? now = s.rankNow;
  final String then = 'المركز ${s.rankIfEnded} من ${s.players}';
  return now == null
      ? 'لو انتهت الآن: $then في ترتيب الشهر'
      : 'مركزك في الشهر $now، ولو انتهت الآن: $then';
}
