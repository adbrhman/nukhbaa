import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:application/src/scoring/rescore_earlier_kickoff.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Keeps a fixture already on the schedule in step with its provider's
/// kickoff (audit C-03). The fixtures sync asks it about the days ahead; the
/// results sync asks it just before recording a result, the last time the
/// provider's kickoff is seen.
///
/// The prediction lock, the reveal and the results window all follow
/// `kickoff_at`: a match brought forward would stay open while it is played,
/// and one put back would lock early and miss its result.
///
/// * The provider's two teams must be the catalog ids on file, so a match
///   linked to the wrong fixture (C-04) never drags that fixture's kickoff.
/// * A kickoff brought forward is moved even after the stored one passed:
///   an earlier kickoff never re-opens the lock, and `ScoreFixture` gives
///   nothing to a prediction sent after it. A fixture already scored is
///   scored again ([RescoreEarlierKickoff]).
/// * A kickoff put back is moved only while the stored one is still ahead,
///   the freeze rule of `CorrectFixtureSchedule`: a later kickoff for a
///   match that has started would re-open the lock.
/// * The new kickoff must fall in the same monthly contest.
///
/// Whatever it may not do is left for an admin: a note for the log and a
/// [ProviderSyncAttention], which the scheduler keeps in the error log so
/// the admins are told. Never throws.
final class FollowProviderKickoff {
  /// Creates the follower over its collaborators.
  const FollowProviderKickoff({
    required FixtureScheduleRepository fixtureScheduleRepository,
    required CompetitionRepository competitionRepository,
    RescoreEarlierKickoff? rescoreEarlierKickoff,
    this.kickoffTolerance = const Duration(minutes: 1),
  }) : _schedules = fixtureScheduleRepository,
       _competitions = competitionRepository,
       _rescore = rescoreEarlierKickoff;

  final FixtureScheduleRepository _schedules;
  final CompetitionRepository _competitions;

  /// Scores a fixture again once its kickoff came earlier; null in tests
  /// that do not look at it, where nothing is scored again.
  final RescoreEarlierKickoff? _rescore;

  /// A provider kickoff closer than this to the stored one is left alone.
  final Duration kickoffTolerance;

  /// Compares fixture [fixtureId] with the provider's [match] at [nowUtc]
  /// and moves its kickoff when that is allowed; writes only when [apply].
  ///
  /// [homeTeamId] and [awayTeamId] are the catalog ids the provider's teams
  /// map to, null when unmapped. [months] are the monthly contests when the
  /// caller already has them; otherwise they are read when needed. What an
  /// admin must look at is added to [attention]. Returns the note for the
  /// log, or null when the kickoff already agrees or the match is one to
  /// leave alone.
  Future<String?> call({
    required String fixtureId,
    required ProviderMatch match,
    required String? homeTeamId,
    required String? awayTeamId,
    required DateTime nowUtc,
    required bool apply,
    required List<ProviderSyncAttention> attention,
    List<CompetitionSeason>? months,
  }) async {
    final refResult = FixtureRef.tryParse(fixtureId);
    if (refResult is Err<FixtureRef>) {
      return 'kickoff check skipped (${refResult.error.code}): $fixtureId';
    }
    final found = await _schedules.findByFixture(
      (refResult as Ok<FixtureRef>).value,
    );
    if (found is Err<FixtureSchedule?>) {
      return 'kickoff check failed (${found.error.code}): $fixtureId';
    }
    final stored = (found as Ok<FixtureSchedule?>).value;
    if (stored == null) {
      return null;
    }
    final storedAt = stored.kickoffAt.toUtc();
    final providerAt = match.kickoffAt.toUtc();
    if (storedAt.difference(providerAt).abs() < kickoffTolerance) {
      return null;
    }

    final game = '${stored.homeTeam} - ${stored.awayTeam}';
    final label =
        '$game ${storedAt.toIso8601String()} -> '
        '${providerAt.toIso8601String()}';
    final times =
        'المسجّل ${riyadhClock(storedAt)}، وعند المزوّد '
        '${riyadhClock(providerAt)} بتوقيت الرياض';
    void ask(String code, String message) => attention.add(
      ProviderSyncAttention(code: code, match: game, message: message),
    );

    if (homeTeamId == null ||
        awayTeamId == null ||
        stored.homeTeamId?.value != homeTeamId ||
        stored.awayTeamId?.value != awayTeamId) {
      ask('provider_sync.kickoff_teams_differ', _teamsDiffer(game, times));
      return 'kickoff differs but the teams are not the ones on file, '
          'needs admin: $label';
    }
    // Earlier never re-opens the lock, so it is followed at any time.
    final broughtForward = providerAt.isBefore(storedAt);
    if (!broughtForward && !storedAt.isAfter(nowUtc)) {
      // Put back after the stored kickoff passed: moving it would re-open
      // the lock. A played match is left alone; one still to be played
      // needs an admin.
      if (match.status != ProviderMatchStatus.scheduled) {
        return null;
      }
      ask('provider_sync.kickoff_put_back_late', _putBackLate(game, times));
      return 'kickoff changed after the stored one passed, needs admin: '
          '$label';
    }

    var contests = months;
    if (contests == null) {
      final listed = await _competitions.listMonthlySeasons();
      if (listed is Err<List<CompetitionSeason>>) {
        return 'kickoff check failed (${listed.error.code}): $label';
      }
      contests = (listed as Ok<List<CompetitionSeason>>).value
          .where(isMonthlyContest)
          .toList(growable: false);
    }
    if (monthContaining(contests, providerAt)?.id.value !=
        monthContaining(contests, storedAt)?.id.value) {
      ask('provider_sync.kickoff_other_month', _otherMonth(game, times));
      return 'kickoff moved to another month, needs admin: $label';
    }
    if (!apply) {
      return 'would move kickoff: $label';
    }

    final moved = FixtureSchedule.create(
      fixture: stored.fixture,
      homeTeam: stored.homeTeam,
      awayTeam: stored.awayTeam,
      kickoffAt: providerAt,
      homeTeamId: stored.homeTeamId,
      awayTeamId: stored.awayTeamId,
      leagueId: stored.leagueId,
      isTest: stored.isTest,
    );
    if (moved is Err<FixtureSchedule>) {
      ask('provider_sync.kickoff_move_failed', _moveFailed(game, times));
      return 'kickoff move failed (${moved.error.code}): $label';
    }
    final saved = await _schedules.upsert((moved as Ok<FixtureSchedule>).value);
    if (saved is Err<void>) {
      ask('provider_sync.kickoff_move_failed', _moveFailed(game, times));
      return 'kickoff move failed (${saved.error.code}): $label';
    }

    final rescore = _rescore;
    if (!broughtForward || rescore == null) {
      return 'moved kickoff: $label';
    }
    final rescored = await rescore(stored.fixture);
    if (rescored is Err<bool>) {
      ask('provider_sync.rescore_failed', _rescoreFailed(game, times));
      return 'moved kickoff, rescore failed (${rescored.error.code}): $label';
    }
    return (rescored as Ok<bool>).value
        ? 'moved kickoff and rescored: $label'
        : 'moved kickoff: $label';
  }

  static String _teamsDiffer(String game, String times) =>
      '«$game»: تغيّر موعدها عند المزوّد ($times)، لكن فريقيها عنده غير '
      'المسجّلين عندنا، فلم يُنقل. تحقّق من ربط المباراة ثم صحّح موعدها من '
      '«تعديل مباراة».';

  static String _putBackLate(String game, String times) =>
      '«$game»: تأخّر موعدها بعد مرور الموعد المسجّل ($times). التوقعات '
      'مقفلة بالموعد القديم ولا يُعاد فتحها؛ إن أُجّلت إلى يوم آخر فأخفِها.';

  static String _otherMonth(String game, String times) =>
      '«$game»: صار موعدها عند المزوّد في شهر آخر ($times)، فلم يُنقل. '
      'صحّحه من «تعديل مباراة» أو أخفِ المباراة.';

  static String _moveFailed(String game, String times) =>
      '«$game»: تعذّر نقل موعدها ($times). صحّحه من «تعديل مباراة».';

  static String _rescoreFailed(String game, String times) =>
      '«$game»: قُدّم موعدها بعد احتسابها ($times) وتعذّرت إعادة الاحتساب. '
      'اضغط «احتساب المباراة» لها في «النتائج والاحتساب».';
}
