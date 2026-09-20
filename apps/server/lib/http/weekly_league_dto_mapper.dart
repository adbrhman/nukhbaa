import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

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
          points: placing.entry.points,
          exactCount: placing.entry.exactCount,
          decidedCount: placing.entry.decidedCount,
          projectedOutcome: placing.outcome.wireName,
          isMe: placing.entry.userId == league.readerId,
        ),
    ],
  );
}

/// Formats a UTC-midnight day as `YYYY-MM-DD`.
String _isoDay(DateTime day) {
  final utc = day.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}
