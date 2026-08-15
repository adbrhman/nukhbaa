import 'package:domain/src/competition/round.dart';
import 'package:domain/src/competition/round_status.dart';

/// Whether [round] is currently predictable by a participant — the
/// sequential-round gate (product decision, 2026-08-14): a round only
/// accepts predictions once every EARLIER round (lower [Round.sequence]) in
/// the same season has left [RoundStatus.open].
///
/// This is deliberately STRICTER than [RoundStatus.isOpen] alone. A season's
/// rounds are opened individually via `OpenRound`, ahead of time, so their
/// fixtures can be linked and the ruleset frozen well before kickoff — which
/// otherwise leaves every round in the season simultaneously `open` (and, by
/// [RoundStatus.isOpen] alone, simultaneously predictable) the moment they are
/// all opened. This function is the single place the "predict round 1 before
/// round 2" rule is expressed, so the write path (`SubmitPrediction`) and the
/// read/display projections (the round list, the round-fixtures screen) can
/// never disagree about which round a participant may currently predict.
///
/// [seasonRounds] must be every round belonging to [round]'s season, in any
/// order (a season's rounds are typically already sequence-ordered by
/// [CompetitionRepository.listSeasonRounds], but this function does not rely
/// on that ordering). A round from a different season is ignored, so passing
/// a wider list than strictly necessary — e.g. the full result of
/// `listSeasonRounds` — is always safe.
///
/// The round with the lowest [Round.sequence] in a season (or a round with no
/// earlier sibling present in [seasonRounds]) is predictable as soon as it is
/// itself [RoundStatus.open] — there is nothing earlier to wait for.
bool isRoundPredictable(Round round, Iterable<Round> seasonRounds) {
  if (!round.status.isOpen) return false;
  for (final other in seasonRounds) {
    if (other.seasonId != round.seasonId) continue;
    if (other.sequence < round.sequence && other.status.isOpen) {
      return false;
    }
  }
  return true;
}
