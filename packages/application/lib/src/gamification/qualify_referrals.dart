/// Use-case: pays or holds every invitation that became eligible
/// (migration 0073). Driven by the scheduler, never by a request.
library;

import 'package:application/src/gamification/ports/referral_repository.dart';
import 'package:shared/shared.dart';

/// Pays one invitation point for every invitee that now has a confirmed
/// account, a monthly participation and a prediction graded on a decided
/// fixture; holds the suspicious ones for an admin. The rules and the
/// once-only guarantee are the database's (`gamification.qualify_referrals`
/// and the unique dedupe key of `gamification.events`), so a repeat is a
/// no-op. Returns the number of events written.
final class QualifyReferrals {
  /// Creates the use-case over its store.
  const QualifyReferrals({required ReferralRepository referrals})
    : _referrals = referrals;

  final ReferralRepository _referrals;

  /// Runs one sweep at [now].
  Future<Result<int>> call({required DateTime now}) =>
      _referrals.qualify(now: now.toUtc());
}
