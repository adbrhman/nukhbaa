import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';
import 'package:server/http/avatar_url.dart';

/// Projects the caller's weekly-league reading onto its versioned wire shape
/// (API ADR, Section 4), in one place.
///
/// Integrity boundary (Axioms 2/5): every number here is server-produced. The
/// rank, the points and the projected outcome are echoed exactly as the
/// policy and the standings reader produced them; there is no inverse, the
/// client never sends a place or a total.
///
/// Days cross the wire as plain `YYYY-MM-DD` Riyadh dates, never as instants:
/// the week boundary belongs to the server.
///
/// The one thing built here rather than echoed is a member's picture
/// address: the route shape (`avatarUrlOf`) applied to the version the
/// profile reader returned. A member with no picture gets a null address;
/// one with no profile at all also gets an empty name.
MyWeeklyLeagueDto myWeeklyLeagueToDto(MyWeeklyLeague league) {
  final monday = WeeklyLeaguePolicy.weekStartOf(league.seat.weekStart);
  final sunday = monday.add(const Duration(days: 6));

  return MyWeeklyLeagueDto(
    weekStart: _isoDay(monday),
    weekEnd: _isoDay(sunday),
    tier: league.seat.tier.level,
    groupIndex: league.seat.groupIndex,
    myRank: league.myRank,
    promotionZone: league.promotionZone,
    relegationZone: league.relegationZone,
    entries: [
      for (final placing in league.placings)
        WeeklyLeagueEntryDto(
          rank: placing.rank,
          userId: placing.entry.userId.value,
          displayName: league.profiles[placing.entry.userId]?.displayName ?? '',
          points: placing.entry.points,
          exactCount: placing.entry.exactCount,
          decidedCount: placing.entry.decidedCount,
          projectedOutcome: placing.outcome.wireName,
          isMe: placing.entry.userId == league.readerId,
          avatarUrl: _avatarUrlOf(placing.entry.userId, league.profiles),
        ),
    ],
  );
}

/// The relative URL of [userId]'s picture, or null when the profile reader
/// returned no picture version for them.
String? _avatarUrlOf(
  UserId userId,
  Map<UserId, WeeklyLeagueMemberProfile> profiles,
) {
  final updatedAt = profiles[userId]?.avatarUpdatedAt;
  if (updatedAt == null) {
    return null;
  }
  return avatarUrlOf(userId: userId, updatedAt: updatedAt);
}

/// Formats a UTC-midnight day as `YYYY-MM-DD`.
String _isoDay(DateTime day) {
  final utc = day.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}
