/// Use-case: the caller's invitation code and counters (migration 0073).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/ports/referral_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The caller's invitation card.
final class ReferralSummary {
  /// Creates the card.
  const ReferralSummary({
    required this.code,
    required this.counts,
    required this.monthCap,
  });

  /// The caller's fixed invitation code.
  final String code;

  /// The caller's counters.
  final ReferralCounts counts;

  /// The most invitation points one month can count.
  final int monthCap;
}

/// Reads (and on first use creates) the caller's invitation code, with the
/// counters of the month and the sporting season open now.
///
/// [installId] is the app's install id; when well formed it is remembered
/// (hashed) so an invitee on the inviter's own install is held for review.
/// Never throws; returns a typed [Result].
final class GetMyReferral {
  /// Creates the use-case over its collaborators.
  const GetMyReferral({
    required ReferralRepository referrals,
    required Clock clock,
  }) : _referrals = referrals,
       _clock = clock;

  final ReferralRepository _referrals;
  final Clock _clock;

  /// The monthly cap, the same number `gamification.referral_month_points`
  /// applies.
  static const int monthCap = 20;

  /// The shape of an install id the app sends.
  static final RegExp installIdPattern = RegExp(r'^[0-9A-Za-z-]{8,64}$');

  /// Runs the use-case for [principal].
  Future<Result<ReferralSummary>> call({
    required AuthenticatedUser principal,
    String? installId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final codeResult = await _referrals.ensureCode(principal.userId);
    if (codeResult is Err<String>) {
      return Result.err(codeResult.error);
    }
    final DateTime now = _clock.nowUtc();
    if (installId != null && installIdPattern.hasMatch(installId)) {
      // A mark is a signal for review, never a reason to fail the read.
      await _referrals.markInstall(
        userId: principal.userId,
        installId: installId,
        now: now,
      );
    }
    final countsResult = await _referrals.counts(
      userId: principal.userId,
      now: now,
      seasonStartYear: SportingSeason.containing(now).startYear,
    );
    return switch (countsResult) {
      Err<ReferralCounts>(:final error) => Result.err(error),
      Ok<ReferralCounts>(:final value) => Result.ok(
        ReferralSummary(
          code: (codeResult as Ok<String>).value,
          counts: value,
          monthCap: monthCap,
        ),
      ),
    };
  }
}
