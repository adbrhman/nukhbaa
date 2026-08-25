/// Projects the read-only Competition-browse aggregates onto their versioned
/// wire shapes (API ADR §4), so the GET browse surface
/// (`GET /competitions`, `GET /competitions/{id}`, `GET /rounds/{id}`,
/// `GET /rounds/{id}/fixtures`) shapes a competition / round / fixture-link
/// identically everywhere.
///
/// Added for the Flutter client's Competition-browse scope (BLOCKER FA-1,
/// 2026-07-13). These are pure read projections — the client never sends any of
/// them back; there is no inverse. They ADD nothing to the existing DTO shapes
/// ([CompetitionDto]/[RoundDto]/[RoundFixtureDto], already shipped by
/// `packages/contracts`): the write routes build the same shapes inline, and
/// this mapper simply reuses them so the read surface never drifts from the
/// write surface.
///
/// Integrity boundary: a round DTO deliberately exposes only the ruleset
/// *version*, never the opaque frozen [RulesetSnapshot] payload (a Scoring-owned
/// internal — Application ADR §2.10); a fixture-link names a fixture by id only
/// (Axiom 3); nothing here carries a group reference (Axiom 4) or any points
/// (Axiom 5).
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects a [Competition] onto its wire shape [CompetitionDto].
CompetitionDto competitionToDto(Competition competition) {
  return CompetitionDto(
    id: competition.id.value,
    name: competition.name,
    format: competition.format.wireValue,
    visibility: competition.visibility.wireValue,
  );
}

/// Projects a [CompetitionSeason] onto its wire shape [SeasonDto].
///
/// Used by the season-browse read (`GET /competitions/{id}/seasons`, DEFECT
/// AD-2 scope closure) so the season list shapes each season identically to the
/// `StartSeason` command's `201` response (which builds the same [SeasonDto]
/// inline). No competition/round ref beyond the owning competition id, no points
/// (Axioms 4/5).
SeasonDto seasonToDto(CompetitionSeason season) {
  return SeasonDto(
    id: season.id.value,
    competitionId: season.competitionId.value,
    label: season.label,
  );
}

/// Projects a [Round] onto its wire shape [RoundDto], exposing only the ruleset
/// *version* (never the opaque frozen snapshot).
///
/// [seasonRounds] must be every round in [round]'s season (any order) — it is
/// required, not optional, so a call site can never forget it and silently
/// under-report [RoundDto.isPredictable] as `false` for a round that is
/// genuinely predictable. Every route that builds a [RoundDto] fetches the
/// season's rounds via `ListSeasonRounds`/`CompetitionRepository.listSeasonRounds`
/// before calling this (see `GET/POST /seasons/{id}/rounds`, `GET /rounds/{id}`,
/// `POST /rounds/{id}/lock`), so the flag is always computed the same way,
/// everywhere a round crosses the wire.
RoundDto roundToDto(Round round, {required List<Round> seasonRounds}) {
  return RoundDto(
    id: round.id.value,
    seasonId: round.seasonId.value,
    sequence: round.sequence,
    predictionDeadline: round.predictionDeadline.toIso8601String(),
    status: round.status.wireValue,
    rulesetVersion: round.ruleset.rulesetVersion,
    isPredictable: isRoundPredictable(round, seasonRounds),
  );
}

/// Projects a [RoundFixture] link onto its wire shape [RoundFixtureDto].
RoundFixtureDto roundFixtureToDto(RoundFixture link) {
  return RoundFixtureDto(
    roundId: link.roundId.value,
    fixtureId: link.fixture.value,
    displayOrder: link.displayOrder,
  );
}

/// Projects a [RoundFixtureCard] onto its wire shape [RoundFixtureCardDto]
/// (`GET /rounds/{id}/fixtures`, Session decision 2026-08-07).
RoundFixtureCardDto roundFixtureCardToDto(RoundFixtureCard card) {
  return RoundFixtureCardDto(
    roundId: card.roundId.value,
    fixtureId: card.fixtureId.value,
    displayOrder: card.displayOrder,
    homeTeam: card.homeTeam,
    awayTeam: card.awayTeam,
    kickoffAt: card.kickoffAt?.toIso8601String(),
  );
}

/// Projects a [SeasonFixtureCard] onto its wire shape [SeasonFixtureCardDto]
/// (`GET /seasons/{id}/fixtures`, Axiom 4 Amendment).
SeasonFixtureCardDto seasonFixtureCardToDto(SeasonFixtureCard card) {
  return SeasonFixtureCardDto(
    seasonId: card.seasonId.value,
    fixtureId: card.fixtureId.value,
    homeTeam: card.homeTeam,
    awayTeam: card.awayTeam,
    kickoffAt: card.kickoffAt?.toIso8601String(),
  );
}

/// Projects a [MatchFeedEntry] onto its wire shape [MatchFeedItemDto]
/// (`GET /feed/matches`, the server-side aggregate read). Reuses
/// [roundFixtureCardToDto]'s nested projection verbatim so a fixture's shape
/// never drifts between the single-round and aggregate reads.
MatchFeedItemDto matchFeedEntryToDto(MatchFeedEntry entry) {
  return MatchFeedItemDto(
    competitionName: entry.competitionName,
    roundId: entry.roundId.value,
    rulesetVersion: entry.rulesetVersion,
    fixture: roundFixtureCardToDto(entry.fixture),
  );
}
