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
@riverpod
Future<List<MatchFeedItem>> matchesFeed(Ref ref) async {
  final CompetitionApi api = ref.watch(competitionApiProvider);
  final List<CompetitionDto> competitions = _unwrap(
    await api.listCompetitions(),
  );

  final List<MatchFeedItem> items = <MatchFeedItem>[];
  for (final CompetitionDto competition in competitions) {
    final List<SeasonDto> seasons = _unwrap(
      await api.listCompetitionSeasons(competition.id),
    );
    for (final SeasonDto season in seasons) {
      final List<RoundDto> rounds = _unwrap(
        await api.listSeasonRounds(season.id),
      );
      for (final RoundDto round in rounds) {
        if (round.status != openRoundStatus) continue;
        final List<RoundFixtureCardDto> fixtures = _unwrap(
          await api.browseRoundFixtures(round.id),
        );
        for (final RoundFixtureCardDto fixture in fixtures) {
          items.add(
            MatchFeedItem(
              competitionName: competition.name,
              roundId: round.id,
              rulesetVersion: round.rulesetVersion,
              fixture: fixture,
            ),
          );
        }
      }
    }
  }
  return items;
}
