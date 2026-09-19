/// Use-case: record the caller's own offset from UTC.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lets an authenticated user report the clock offset of the device they are
/// holding (P1-1). Mirrors [UpdateDisplayName]: every user may write their
/// OWN offset and there is no surface for writing anyone else's, so the
/// principal is the whole of the authority check — no repository lookup is
/// needed to establish that authority.
///
/// **This does not move a day boundary.** The daily challenge, the streak and
/// `gamification.daily_active_users` (migration 0054) are all bounded by the
/// Riyadh day, exactly as `sync_provider_fixtures`, `sync_provider_results`
/// and `reminder_sends` already are. One shared day is what keeps "today's
/// fixtures" a single set and the standings a single table. The offset stored
/// here answers a different question: at what moment on the reader's own
/// clock a notification may arrive (quiet hours, P3-2).
///
/// An offset is not a time zone — it carries no daylight-saving rule — so the
/// client re-reports it on every app start rather than the platform trusting
/// one reading indefinitely. For the Gulf audience the two coincide; for a
/// traveller the latest report is simply the truest reading available without
/// a zone database.
///
/// Never throws; returns a typed [Result].
final class UpdateTimeZoneOffset {
  /// Creates the use-case over its [UserDirectory] port.
  const UpdateTimeZoneOffset({required UserDirectory userDirectory})
    : _userDirectory = userDirectory;

  final UserDirectory _userDirectory;

  /// Records [offsetMinutes] as [principal]'s current offset from UTC.
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required int offsetMinutes,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final validated = User.validateUtcOffsetMinutes(offsetMinutes);
    if (validated is Err<int>) {
      return Result.err(validated.error);
    }

    return _userDirectory.updateUtcOffsetMinutes(
      principal.userId,
      (validated as Ok<int>).value,
    );
  }
}
