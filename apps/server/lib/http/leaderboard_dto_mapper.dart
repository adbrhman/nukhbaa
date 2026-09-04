import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the domain [SeasonLeaderboard] aggregate onto the versioned wire
/// shape [SeasonLeaderboardDto] (API ADR §4), and one [LeaderboardEntry] onto
/// [LeaderboardEntryDto].
///
/// This mapping lives here, once, so the leaderboard read surface
/// (`GET /seasons/{id}/leaderboard`) shapes a standing identically everywhere.
///
/// Integrity boundary (Axioms 2/5): a leaderboard is a **server-produced read
/// value** — the rank, signed total, and entry count are echoed exactly as the
/// domain computed them from the append-only ledger projection; nothing here is
/// client-writable and there is no inverse (the client never sends a
/// leaderboard). The entries are echoed in the aggregate's already-ranked total
/// order (points desc, joinedAt asc, participant-id asc), so the display order
/// is fixed by the domain, not this mapper. Names a participant by id only; no
/// group reference travels on an entry (Axiom 4).
LeaderboardEntryDto leaderboardEntryToDto(LeaderboardEntry entry) {
  return LeaderboardEntryDto(
    rank: entry.rank,
    participantId: entry.participantId.value,
    displayName: entry.displayName,
    totalPoints: entry.totalPoints,
    entryCount: entry.entryCount,
  );
}

/// Shapes a ranked [SeasonLeaderboard] into the whole-board read response
/// [SeasonLeaderboardDto], preserving the aggregate's ranked entry order. An
/// empty [SeasonLeaderboard.entries] shapes an empty `entries` array — a
/// legitimate empty board (a season with no participants), never an error.
Map<String, Object?> seasonLeaderboardToJson(SeasonLeaderboard leaderboard) {
  return SeasonLeaderboardDto(
    seasonId: leaderboard.seasonId.value,
    entries: [
      for (final entry in leaderboard.entries) leaderboardEntryToDto(entry),
    ],
  ).toJson();
}

/// Projects one domain [RoundLeaderboardEntry] onto [RoundLeaderboardEntryDto].
///
/// Same integrity boundary as [leaderboardEntryToDto]: every field is echoed
/// exactly as the domain computed it from the round's already-scored
/// [RoundScore]s — nothing here is client-writable, and there is no inverse.
RoundLeaderboardEntryDto roundLeaderboardEntryToDto(
  RoundLeaderboardEntry entry,
) {
  return RoundLeaderboardEntryDto(
    rank: entry.rank,
    participantId: entry.participantId.value,
    totalPoints: entry.totalPoints,
  );
}

/// Shapes a ranked [RoundLeaderboard] into the whole-board read response
/// [RoundLeaderboardDto], preserving the aggregate's ranked entry order. An
/// empty [RoundLeaderboard.entries] shapes an empty `entries` array — a
/// legitimate empty board (a scored round nobody predicted), never an error.
Map<String, Object?> roundLeaderboardToJson(RoundLeaderboard leaderboard) {
  return RoundLeaderboardDto(
    roundId: leaderboard.roundId.value,
    entries: [
      for (final entry in leaderboard.entries)
        roundLeaderboardEntryToDto(entry),
    ],
  ).toJson();
}

/// Projects one domain [HallOfFameEntry] onto [HallOfFameEntryDto].
///
/// Same integrity boundary as [leaderboardEntryToDto]: every field is echoed
/// exactly as the domain computed it from the append-only ledger projection —
/// nothing here is client-writable, and there is no inverse.
HallOfFameEntryDto hallOfFameEntryToDto(HallOfFameEntry entry) {
  return HallOfFameEntryDto(
    rank: entry.rank,
    userId: entry.userId.value,
    displayName: entry.displayName,
    totalPoints: entry.totalPoints,
    seasonsPlayed: entry.seasonsPlayed,
  );
}

/// Shapes a ranked [HallOfFame] into the whole-board read response
/// [HallOfFameDto], preserving the aggregate's ranked entry order. An empty
/// [HallOfFame.entries] shapes an empty `entries` array — a legitimate empty
/// board (nobody has ever been credited yet), never an error.
Map<String, Object?> hallOfFameToJson(HallOfFame hallOfFame) {
  return HallOfFameDto(
    entries: [
      for (final entry in hallOfFame.entries) hallOfFameEntryToDto(entry),
    ],
  ).toJson();
}

/// Projects one domain `FixtureLeaderboardEntry` onto
/// [FixtureLeaderboardEntryDto].
///
/// Same integrity boundary as [leaderboardEntryToDto]: every field is echoed
/// exactly as the domain computed it from the season's already-scored
/// fixture scores — nothing here is client-writable, and there is no
/// inverse.
FixtureLeaderboardEntryDto fixtureLeaderboardEntryToDto(
  FixtureLeaderboardEntry entry,
) {
  return FixtureLeaderboardEntryDto(
    rank: entry.rank,
    participantId: entry.participantId.value,
    displayName: entry.displayName,
    totalPoints: entry.totalPoints,
    fixturesScored: entry.fixturesScored,
  );
}

/// Shapes a ranked `FixtureLeaderboard` into the whole-board read response
/// [FixtureLeaderboardDto], preserving the aggregate's ranked entry order. An
/// empty `FixtureLeaderboard.entries` shapes an empty `entries` array — a
/// legitimate live/partial state (no fixture scored yet), never an error.
Map<String, Object?> fixtureLeaderboardToJson(FixtureLeaderboard leaderboard) {
  return FixtureLeaderboardDto(
    seasonId: leaderboard.seasonId.value,
    entries: [
      for (final entry in leaderboard.entries)
        fixtureLeaderboardEntryToDto(entry),
    ],
  ).toJson();
}
