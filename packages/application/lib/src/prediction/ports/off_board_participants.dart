/// Port: the participants no board shows (script 261).
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Every participant, of any season, whose account is suspended or hidden
/// now (`identity.users.status = 'suspended'` or `hidden_at`, migration
/// 0207). A suspended or hidden account is on no standing; with this, its
/// predictions and scores are left off each match's board too
/// ([ListFixturePredictions], [GetFixtureScores]).
///
/// A small set, read for every board, so an adapter may hold it briefly: a
/// suspension or a hiding then reaches the boards within that time. Scoring
/// never reads it: it reads [SuspendedPredictorsReader] fresh.
abstract interface class OffBoardParticipants {
  /// The participants off every board; empty when there are none.
  Future<Result<Set<ParticipantId>>> all();
}
