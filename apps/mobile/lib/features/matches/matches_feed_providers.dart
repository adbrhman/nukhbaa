/// The unified **Matches** feed — every currently-open round's fixture(s)
/// across every competition, flattened into one ordered list.
///
/// ## Why this is a client-side read composition, not a new server endpoint
/// The gap this closes is purely presentational: the admin can already open
/// any number of rounds across any competitions (`OpenRound` ->
/// `RegisterFixtureSchedule` -> `LinkFixtureToRound`, unchanged); what was
/// missing was showing all of it in one connected screen instead of the
/// competition -> season -> round -> fixtures drill-down. Composing several
/// existing reads client-side has direct precedent in this app (see the
/// Admin's `round_report.dart`, which merges `GET /rounds/{id}/scores` with
/// `GET /admin/rounds/{id}/predictions`), so this follows the same pattern
/// rather than adding a server aggregate query. No Supabase/schema change is
/// involved — every call below is an existing, ratified `CompetitionApi`
/// read.
///
/// ## Ordering
/// Competitions are walked in the order `GET /competitions` returns them
/// (server/admin order), then each competition's seasons (label order) and
/// rounds (sequence order), then each open round's fixtures (display
/// order). Because every card renders its own competition name + kickoff
/// time (see `matches_feed_screen.dart`), this produces the same visual
/// grouping ("Premier League" block, then "Saudi league" block, ...) the
/// admin described, with no separate section widget needed.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'matches_feed_providers.g.dart';

/// The stable wire status token for an open round — matches
/// `RoundStatus.open.wireValue` on the server (Database/Application ADRs);
/// duplicated as a constant here rather than imported since `apps/mobile`
/// depends on `contracts`, not `domain`.
const String openRoundStatus = 'open';

/// One card in the unified feed: a single open round's fixture, enriched
/// with its owning competition's display name (for the card's league
/// header) and the round's frozen ruleset version.
final class MatchFeedItem {
  /// Creates a feed item.
  const MatchFeedItem({
    required this.competitionName,
    required this.roundId,
    required this.rulesetVersion,
    required this.fixture,
  });

  /// The owning competition's display name (e.g. "الدوري الإنجليزي الممتاز").
  final String competitionName;

  /// The owning round id — predictions are submitted per round
  /// (`predictionControllerProvider(roundId)`), unchanged from the existing
  /// single-round prediction screen.
  final String roundId;

  /// The round's frozen ruleset version (never the opaque snapshot).
  final int rulesetVersion;

  /// The fixture card itself (team names + kickoff; nullable per Axiom 3).
  final RoundFixtureCardDto fixture;
}

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// Walks `GET /competitions` -> `.../seasons` -> `.../rounds` -> every
/// **open** round's `GET /rounds/{id}/fixtures`, flattened into one ordered
/// list. An empty result (no competitions, or none with an open round) is a
/// legitimate `Ok(<empty>)` — the screen shows an "no open matches"
/// affordance, never an error, mirroring every other browse read in this
/// app.
@Riverpod(keepAlive: true)
Future<List<MatchFeedItem>> matchesFeed(Ref ref) async {
  final CompetitionApi api = ref.watch(competitionApiProvider);
  final List<CompetitionDto> competitions = _unwrap(
    await api.listCompetitions(),
  );

  // Fan out each level in parallel (Future.wait) instead of a serial
  // await-in-loop waterfall; order is preserved via index alignment, so
  // the resulting flattening matches the original nested-loop ordering.
  final List<List<SeasonDto>> seasonsByCompetition = await Future.wait(
    competitions.map((c) => api.listCompetitionSeasons(c.id).then(_unwrap)),
  );

  final List<(CompetitionDto, SeasonDto)> compSeasonPairs =
      <(CompetitionDto, SeasonDto)>[
        for (var i = 0; i < competitions.length; i++)
          for (final SeasonDto season in seasonsByCompetition[i])
            (competitions[i], season),
      ];

  final List<List<RoundDto>> roundsByPair = await Future.wait(
    compSeasonPairs.map((p) => api.listSeasonRounds(p.$2.id).then(_unwrap)),
  );

  final List<(CompetitionDto, RoundDto)> openRounds =
      <(CompetitionDto, RoundDto)>[
        for (var i = 0; i < compSeasonPairs.length; i++)
          for (final RoundDto round in roundsByPair[i])
            if (round.status == openRoundStatus) (compSeasonPairs[i].$1, round),
      ];

  final List<List<RoundFixtureCardDto>> fixturesByRound = await Future.wait(
    openRounds.map((p) => api.browseRoundFixtures(p.$2.id).then(_unwrap)),
  );

  return <MatchFeedItem>[
    for (var i = 0; i < openRounds.length; i++)
      for (final RoundFixtureCardDto fixture in fixturesByRound[i])
        MatchFeedItem(
          competitionName: openRounds[i].$1.name,
          roundId: openRounds[i].$2.id,
          rulesetVersion: openRounds[i].$2.rulesetVersion,
          fixture: fixture,
        ),
  ];
}
