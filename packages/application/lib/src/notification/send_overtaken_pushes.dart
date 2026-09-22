import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/gamification/ports/weekly_league_standings_reader.dart';
import 'package:application/src/notification/ports/overtaken_repository.dart';
import 'package:application/src/notification/ports/push_budget_reader.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Scheduled use-case: tell a weekly-league member who was just overtaken,
/// and by whom (plan P3-4c).
///
/// Each sweep ranks every group of the open week ([WeeklyLeaguePolicy.order],
/// the order the table shows), compares it with the marks of the previous
/// sweep (0067), and saves the new marks before anything is sent, so a
/// sweep that fails half-way never reports the same pass twice.
/// [OvertakeDetector] names who passed whom.
///
/// Every push passes [NotificationGate] (the `overtaken` switch, the quiet
/// hours, the shared weekly budget), and a member hears it at most once per
/// group, so once a week. A pass during the quiet hours is simply not told:
/// by morning the table has moved on.
///
/// Returns the number of pushes sent.
final class SendOvertakenPushes {
  /// Creates the use-case over its collaborators.
  const SendOvertakenPushes({
    required OvertakenRepository overtaken,
    required WeeklyLeagueStandingsReader standings,
    required WeeklyLeagueProfileReader profiles,
    required PushBudgetReader budget,
    required PushSender sender,
  }) : _overtaken = overtaken,
       _standings = standings,
       _profiles = profiles,
       _budget = budget,
       _sender = sender;

  final OvertakenRepository _overtaken;
  final WeeklyLeagueStandingsReader _standings;
  final WeeklyLeagueProfileReader _profiles;
  final PushBudgetReader _budget;
  final PushSender _sender;

  /// The notification title.
  static const String title = 'نُخبة';

  /// The notification body: [name] passed the reader, now at [rank].
  static String bodyFor(String name, int rank) =>
      '$name تخطّاك في دوري الأسبوع، أنت الآن في المركز $rank';

  /// Runs one sweep at [now].
  Future<Result<int>> call({required DateTime now}) async {
    final DateTime utcNow = now.toUtc();
    final DateTime weekStart = WeeklyLeaguePolicy.weekStartOf(
      riyadhDayOf(utcNow),
    );
    final leaguesResult = await _overtaken.openLeagues(weekStart: weekStart);
    if (leaguesResult is Err<List<WeeklyLeagueId>>) {
      return Result.err(leaguesResult.error);
    }
    var delivered = 0;
    for (final leagueId in (leaguesResult as Ok<List<WeeklyLeagueId>>).value) {
      final result = await _sweepLeague(leagueId, weekStart, utcNow);
      if (result is Err<int>) {
        return Result.err(result.error);
      }
      delivered += (result as Ok<int>).value;
    }
    return Result.ok(delivered);
  }

  Future<Result<int>> _sweepLeague(
    WeeklyLeagueId leagueId,
    DateTime weekStart,
    DateTime now,
  ) async {
    final entriesResult = await _standings.entriesOf(
      leagueId: leagueId,
      weekStart: weekStart,
    );
    if (entriesResult is Err<List<WeeklyLeagueEntry>>) {
      return Result.err(entriesResult.error);
    }
    final List<UserId> ordered = <UserId>[
      for (final entry in WeeklyLeaguePolicy.order(
        (entriesResult as Ok<List<WeeklyLeagueEntry>>).value,
      ))
        entry.userId,
    ];
    if (ordered.isEmpty) {
      return const Result.ok(0);
    }

    final marksResult = await _overtaken.rankMarks(leagueId);
    if (marksResult is Err<Map<UserId, int>>) {
      return Result.err(marksResult.error);
    }
    final Map<UserId, int> previous =
        (marksResult as Ok<Map<UserId, int>>).value;
    final Map<UserId, int> ranks = <UserId, int>{
      for (var i = 0; i < ordered.length; i++) ordered[i]: i + 1,
    };
    final saved = await _overtaken.saveRankMarks(
      leagueId: leagueId,
      ranks: ranks,
      now: now,
    );
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }

    final passed = OvertakeDetector.detect(
      previous: previous,
      ordered: ordered,
    );
    if (passed.isEmpty) {
      return const Result.ok(0);
    }

    final victims = passed.keys.toList();
    final recipientsResult = await _overtaken.recipients(
      leagueId: leagueId,
      userIds: victims,
    );
    if (recipientsResult is Err<Map<UserId, OvertakenRecipient>>) {
      return Result.err(recipientsResult.error);
    }
    final recipients =
        (recipientsResult as Ok<Map<UserId, OvertakenRecipient>>).value;
    if (recipients.isEmpty) {
      return const Result.ok(0);
    }

    final countsResult = await _budget.sentCountsSince(
      userIds: recipients.keys.toList(),
      fromDate: NotificationGate.weekStartDate(now),
    );
    if (countsResult is Err<Map<String, int>>) {
      return Result.err(countsResult.error);
    }
    final counts = (countsResult as Ok<Map<String, int>>).value;

    final namesResult = await _profiles.profilesOf(
      passed.values.toSet().toList(),
    );
    if (namesResult is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(namesResult.error);
    }
    final names =
        (namesResult as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;

    final String sendDate = NotificationGate.riyadhDate(now);
    final dead = <String>[];
    var delivered = 0;
    for (final victim in victims) {
      final recipient = recipients[victim];
      final name = names[passed[victim]]?.displayName;
      if (recipient == null || recipient.alreadySent || name == null) {
        continue;
      }
      if (!NotificationGate.allows(
        optedIn: recipient.optedIn,
        now: now,
        sentThisWeek: counts[victim.value] ?? 0,
        utcOffsetMinutes: recipient.utcOffsetMinutes,
      )) {
        continue;
      }
      final result = await _sender.send(
        tokens: recipient.tokens,
        title: title,
        body: bodyFor(name, ranks[victim]!),
      );
      if (result is! Ok<List<String>>) {
        continue;
      }
      dead.addAll(result.value);
      delivered++;
      final marked = await _overtaken.markSent(
        userId: victim,
        leagueId: leagueId,
        sendDate: sendDate,
        now: now,
      );
      if (marked is Err<void>) {
        return Result.err(marked.error);
      }
    }

    if (dead.isNotEmpty) {
      await _overtaken.forgetTokens(dead);
    }
    return Result.ok(delivered);
  }
}
