/// Use-case: one head-to-head round of the caller in detail (migration
/// 0100) -- every fixture, the caller's picks, and the opponent's picks on
/// the fixtures that have kicked off.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/get_my_h2h_league.dart';
import 'package:application/src/gamification/h2h_round_phase.dart';
import 'package:application/src/gamification/ports/h2h_round_fixture_reader.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Where one fixture of a round stands.
enum H2hFixtureState {
  /// Not kicked off (or no kickoff registered).
  notStarted('not_started'),

  /// Kicked off, no result recorded yet.
  live('live'),

  /// A result is recorded.
  finished('finished'),

  /// It no longer counts for the round (moved off its day, hidden or a
  /// test fixture): void for both sides.
  voided('void');

  const H2hFixtureState(this.wireName);

  /// The value sent to clients.
  final String wireName;
}

/// One fixture of the round as the caller may see it.
///
/// It carries no reference to what the reader returned: the opponent's
/// pick is here only once this use-case has let it through.
final class H2hRoundFixtureView {
  /// Creates a fixture view.
  const H2hRoundFixtureView({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.kickoffAt,
    required this.state,
    required this.homeGoals,
    required this.awayGoals,
    required this.mine,
    required this.theirs,
    required this.theirsHidden,
  });

  /// The fixture (UUID string).
  final String fixtureId;

  /// The home team's name.
  final String homeTeam;

  /// The away team's name.
  final String awayTeam;

  /// The home team's catalogue id, when known.
  final String? homeTeamId;

  /// The away team's catalogue id, when known.
  final String? awayTeamId;

  /// The kickoff (UTC), or null when none is registered.
  final DateTime? kickoffAt;

  /// Where it stands.
  final H2hFixtureState state;

  /// The recorded home goals, or null before a result.
  final int? homeGoals;

  /// The recorded away goals, or null before a result.
  final int? awayGoals;

  /// The caller's pick, or null.
  final H2hFixturePick? mine;

  /// The opponent's pick: only after kickoff, and null when they made none.
  final H2hFixturePick? theirs;

  /// True while the opponent's pick is withheld because the fixture has not
  /// kicked off. False with the group average.
  final bool theirsHidden;
}

/// One side's counts over a round.
final class H2hSideTotals {
  /// Creates the counts.
  const H2hSideTotals({
    required this.predicted,
    required this.exact,
    required this.doubles,
  });

  /// Counted fixtures predicted.
  final int predicted;

  /// Exact scorelines hit.
  final int exact;

  /// Counted fixtures doubled.
  final int doubles;
}

/// One round of the caller in detail.
///
/// It carries the round's points but not the policy's `H2hMatch`: during a
/// live round that match also says whether the opponent predicted at all,
/// fixtures not kicked off included.
final class MyH2hRoundDetail {
  /// Creates a reading.
  const MyH2hRoundDetail({
    required this.round,
    required this.opponentId,
    required this.myPoints,
    required this.opponentPoints,
    required this.phase,
    required this.result,
    required this.opponentProfile,
    required this.firstKickoff,
    required this.fixtures,
    required this.mine,
    required this.theirs,
  });

  /// The round.
  final H2hRound round;

  /// The caller's opponent, or null when they play the group average.
  final UserId? opponentId;

  /// The caller's stored points in the round; null before it starts and
  /// when it is void.
  final int? myPoints;

  /// The opponent's stored points, or the group average; null as
  /// [myPoints] is.
  final double? opponentPoints;

  /// The round's phase in its month.
  final H2hRoundPhase phase;

  /// The result the screen shows (`h2hShownResultOf`), or null.
  final H2hMatchResult? result;

  /// The opponent's name and picture version, or null with the group
  /// average.
  final WeeklyLeagueMemberProfile? opponentProfile;

  /// The first kickoff among the fixtures that count, when known.
  final DateTime? firstKickoff;

  /// Every fixture of the round, by kickoff (none registered last).
  final List<H2hRoundFixtureView> fixtures;

  /// The caller's counts over the fixtures that count.
  final H2hSideTotals mine;

  /// The opponent's counts over the fixtures that count and have kicked
  /// off; null with the group average.
  final H2hSideTotals? theirs;
}

/// Reads one round of the caller's month in detail.
///
/// **The opponent's picks stay secret until each fixture kicks off.** A pick
/// of theirs leaves this use-case only for a fixture with a registered
/// kickoff that `FixtureLock` finds locked against the server [Clock] -- the
/// same rule that closes predictions. A fixture with no kickoff stays
/// hidden. Their counts cover the same fixtures only, and the live result
/// shown is `h2hShownResultOf`, which weighs stored points alone.
///
/// **It reads; it does not score.** Points are the stored scores; the
/// match, the opponent and the round state are [GetMyH2hLeague]'s.
///
/// Never throws; returns a typed [Result]. A caller with no seat this month
/// gets `h2h.not_seated`; a round number the month does not have,
/// `h2h.round_unknown`.
final class GetMyH2hRound {
  /// Creates the use-case over its collaborators.
  const GetMyH2hRound({
    required GetMyH2hLeague league,
    required H2hRoundFixtureReader fixtures,
    required Clock clock,
  }) : _league = league,
       _fixtures = fixtures,
       _clock = clock;

  final GetMyH2hLeague _league;
  final H2hRoundFixtureReader _fixtures;
  final Clock _clock;

  /// Reads round [round] of [principal]'s month.
  Future<Result<MyH2hRoundDetail>> call({
    required AuthenticatedUser principal,
    required int round,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final leagueResult = await _league(principal: principal);
    if (leagueResult is Err<MyH2hLeague>) {
      return Result.err(leagueResult.error);
    }
    final league = (leagueResult as Ok<MyH2hLeague>).value;
    if (league.state != H2hLeagueState.open) {
      return const Result.err(
        AppError.invariant(
          'h2h.not_seated',
          'The caller holds no seat this month',
        ),
      );
    }
    MyH2hRound? view;
    for (final candidate in league.rounds) {
      if (candidate.round.number == round) {
        view = candidate;
        break;
      }
    }
    if (view == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_unknown',
          'The month has no round with this number',
        ),
      );
    }

    final now = _clock.nowUtc().toUtc();
    final opponent = view.opponentId;
    final readResult = await _fixtures.fixturesOf(
      round: view.round,
      reader: league.readerId,
      opponent: opponent,
      nowUtc: now,
    );
    if (readResult is Err<List<H2hRoundFixture>>) {
      return Result.err(readResult.error);
    }
    final read = List<H2hRoundFixture>.of(
      (readResult as Ok<List<H2hRoundFixture>>).value,
    )..sort(_byKickoff);

    final fixtures = <H2hRoundFixtureView>[];
    var myPredicted = 0;
    var myExact = 0;
    var myDoubles = 0;
    var theirPredicted = 0;
    var theirExact = 0;
    var theirDoubles = 0;
    DateTime? firstKickoff;
    for (final fixture in read) {
      final kickoff = fixture.kickoffAt?.toUtc();
      final started = hasKickedOff(kickoffAt: kickoff, nowUtc: now);
      final revealed = opponent != null && started;
      final theirs = revealed ? fixture.theirs : null;

      if (fixture.counted) {
        if (kickoff != null &&
            (firstKickoff == null || kickoff.isBefore(firstKickoff))) {
          firstKickoff = kickoff;
        }
        final mine = fixture.mine;
        if (mine != null) {
          myPredicted++;
          if (mine.exact) {
            myExact++;
          }
          if (mine.isDouble) {
            myDoubles++;
          }
        }
        if (theirs != null) {
          theirPredicted++;
          if (theirs.exact) {
            theirExact++;
          }
          if (theirs.isDouble) {
            theirDoubles++;
          }
        }
      }

      final H2hFixtureState state;
      if (!fixture.counted) {
        state = H2hFixtureState.voided;
      } else if (fixture.homeGoals != null && fixture.awayGoals != null) {
        state = H2hFixtureState.finished;
      } else if (started) {
        state = H2hFixtureState.live;
      } else {
        state = H2hFixtureState.notStarted;
      }

      fixtures.add(
        H2hRoundFixtureView(
          fixtureId: fixture.fixtureId,
          homeTeam: fixture.homeTeam,
          awayTeam: fixture.awayTeam,
          homeTeamId: fixture.homeTeamId,
          awayTeamId: fixture.awayTeamId,
          kickoffAt: kickoff,
          state: state,
          homeGoals: fixture.homeGoals,
          awayGoals: fixture.awayGoals,
          mine: fixture.mine,
          theirs: theirs,
          theirsHidden: opponent != null && !started,
        ),
      );
    }

    final match = view.match;
    return Result.ok(
      MyH2hRoundDetail(
        round: view.round,
        opponentId: opponent,
        myPoints: match?.points,
        opponentPoints: match?.opponentPoints,
        phase: h2hRoundPhasesOf(league.rounds)[view.round.number]!,
        result: h2hShownResultOf(view),
        opponentProfile: opponent == null ? null : league.profiles[opponent],
        firstKickoff: firstKickoff,
        fixtures: List<H2hRoundFixtureView>.unmodifiable(fixtures),
        mine: H2hSideTotals(
          predicted: myPredicted,
          exact: myExact,
          doubles: myDoubles,
        ),
        theirs: opponent == null
            ? null
            : H2hSideTotals(
                predicted: theirPredicted,
                exact: theirExact,
                doubles: theirDoubles,
              ),
      ),
    );
  }

  /// Whether a fixture kicking off at [kickoffAt] has kicked off at
  /// [nowUtc]: `FixtureLock`, the rule that closes predictions. No kickoff,
  /// or one the lock refuses, has not.
  static bool hasKickedOff({
    required DateTime? kickoffAt,
    required DateTime nowUtc,
  }) {
    if (kickoffAt == null) {
      return false;
    }
    final lock = FixtureLock.at(kickoffAt: kickoffAt, nowUtc: nowUtc);
    return lock is Ok<FixtureLock> && lock.value.isLocked;
  }

  static int _byKickoff(H2hRoundFixture a, H2hRoundFixture b) {
    final ka = a.kickoffAt;
    final kb = b.kickoffAt;
    if (ka != null && kb != null) {
      final byTime = ka.compareTo(kb);
      if (byTime != 0) {
        return byTime;
      }
    } else if (ka != null) {
      return -1;
    } else if (kb != null) {
      return 1;
    }
    return a.fixtureId.compareTo(b.fixtureId);
  }
}
