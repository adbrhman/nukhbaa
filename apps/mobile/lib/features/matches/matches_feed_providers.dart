/// The unified **Matches** feed — every currently-open round's fixture(s)
/// across every competition, flattened into one ordered list.
///
/// ## Server-side aggregate read (2026-08-17)
/// Consumes `GET /feed/matches` directly — a single request. Previously this
/// provider composed the feed client-side (`GET /competitions` ->
/// `.../seasons` -> `.../rounds` -> per-open-round
/// `GET /rounds/{id}/fixtures`), which degenerated into dozens of HTTP
/// round-trips — most of them empty — once a season accumulated many
/// opened-but-unlinked rounds (measured: ~50 requests, >1 minute on a real
/// mobile network for one screen). The server now performs the same
/// aggregation in three batched database reads (`ListMatchesFeed`
/// use-case); this provider only shapes the response into [MatchFeedItem].
///
/// ## Ordering
/// Server-determined: competition name order, then each competition's open
/// rounds in sequence order, then each round's fixtures in display order —
/// unchanged from the prior client-side composition, so the rendered grouping
/// ("Premier League" block, then "Saudi league" block, ...) is identical.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'matches_feed_providers.g.dart';

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

  /// Builds a feed item from its wire shape.
  factory MatchFeedItem.fromDto(MatchFeedItemDto dto) => MatchFeedItem(
    competitionName: dto.competitionName,
    roundId: dto.roundId,
    rulesetVersion: dto.rulesetVersion,
    fixture: dto.fixture,
  );

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

/// Fetches `GET /feed/matches` and shapes it into [MatchFeedItem]s. An empty
/// result (no open rounds anywhere, or none with a linked fixture) is a
/// legitimate `Ok(<empty>)` — the screen shows an "no open matches"
/// affordance, never an error, mirroring every other browse read in this
/// app.
@Riverpod(keepAlive: true)
Future<List<MatchFeedItem>> matchesFeed(Ref ref) async {
  final CompetitionApi api = ref.watch(competitionApiProvider);
  final List<MatchFeedItemDto> feed = _unwrap(await api.getMatchesFeed());
  return [for (final dto in feed) MatchFeedItem.fromDto(dto)];
}
