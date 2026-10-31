/// Use-cases: the admin's desk for relegation for absence (NK183, migration
/// 0189): what the rules see now, a relegation by hand, and a round taken
/// out of the count.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/h2h_seat_move_store.dart';
import 'package:application/src/gamification/ports/h2h_sheet_reader.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/gamification/run_h2h_absence.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// An elite player on the watch list: absent from the latest counted
/// rounds.
final class H2hAbsenceWatch {
  /// Creates a watch row.
  const H2hAbsenceWatch({
    required this.seat,
    required this.groupNumber,
    required this.absentRounds,
    required this.warned,
  });

  /// His seat.
  final H2hHeldSeat seat;

  /// His group as players see it (1..4).
  final int groupNumber;

  /// The counted rounds he missed in a row, oldest first.
  final List<H2hCountedRound> absentRounds;

  /// Whether the second-absence warning went out.
  final bool warned;
}

/// A possible substitute, in the order the rules would take them.
final class H2hAbsenceCandidate {
  /// Creates a candidate row.
  const H2hAbsenceCandidate({
    required this.seat,
    required this.groupNumber,
    required this.facts,
  });

  /// His extra seat.
  final H2hHeldSeat seat;

  /// His group as players see it (5 and up).
  final int groupNumber;

  /// What he is ranked on.
  final H2hCandidateFacts facts;
}

/// One round of the month as the absence count sees it.
final class H2hAbsenceRoundView {
  /// Creates a round view.
  const H2hAbsenceRoundView({
    required this.round,
    required this.counted,
    required this.excusal,
    required this.absent,
  });

  /// The round.
  final H2hRound round;

  /// Whether it counts (locked, past its last kickoff, a fixture left, not
  /// excused).
  final bool counted;

  /// The admin's excusal, when there is one.
  final H2hRoundExcusal? excusal;

  /// Elite holders who did not predict in it (counted rounds only).
  final int absent;
}

/// The admin's view of relegation for absence this month.
final class H2hAbsenceView {
  /// Creates a view.
  const H2hAbsenceView({
    required this.monthStart,
    required this.active,
    required this.nextRound,
    required this.relegatesAt,
    required this.rounds,
    required this.watch,
    required this.candidates,
    required this.moves,
    required this.profiles,
    this.groupNumbers = const {},
  });

  /// The month.
  final DateTime monthStart;

  /// Whether the rules run this month (an elite month that was drawn).
  final bool active;

  /// The next round not started, when there is one.
  final H2hRound? nextRound;

  /// When the system swaps the seats before [nextRound] (an hour before its
  /// first kickoff), or null.
  final DateTime? relegatesAt;

  /// The month's rounds with their place in the count.
  final List<H2hAbsenceRoundView> rounds;

  /// Elite players absent from the latest counted round(s), longest run
  /// first.
  final List<H2hAbsenceWatch> watch;

  /// The next substitutes, best first (ten at most).
  final List<H2hAbsenceCandidate> candidates;

  /// The month's swaps, oldest first.
  final List<H2hSeatMove> moves;

  /// Names and pictures of everybody above.
  final Map<UserId, WeeklyLeagueMemberProfile> profiles;

  /// Each group of the month as players number it (1..4 elite, 5 and up).
  final Map<H2hLeagueId, int> groupNumbers;
}

/// The admin's desk for relegation for absence. Admin only; every method
/// returns a typed [Result] and never throws.
///
/// * [view]: the month's count, the watch list, the next substitutes in the
///   order the rules take them, and every swap with its facts.
/// * [relegate]: an admin relegates an elite player by hand (cheating, a
///   breach), with a reason, from the next round not started (round 2 to
///   19); the substitute is the one the rules would take. He never comes
///   back in the month. Refused: `h2h.reason_required`,
///   `h2h.not_elite_player`, `h2h.already_relegated`, `h2h.no_next_round`,
///   `h2h.no_substitute`, `h2h.absence_inactive`.
/// * [excuse]: takes a round of this month or the month before out of the
///   absence count (the app was down), with a reason; a swap already made
///   stays. Refused: `h2h.reason_required`, `h2h.round_unknown`,
///   `h2h.round_not_started`.
final class AdminH2hAbsence {
  /// Creates the desk over its collaborators.
  const AdminH2hAbsence({
    required H2hLeagueStore leagues,
    required H2hRoundStore rounds,
    required H2hSheetReader sheets,
    required H2hSeatMoveStore moves,
    required WeeklyLeagueProfileReader profiles,
    required PushSender sender,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _leagues = leagues,
       _rounds = rounds,
       _sheets = sheets,
       _moves = moves,
       _profiles = profiles,
       _sender = sender,
       _ids = idGenerator,
       _clock = clock;

  final H2hLeagueStore _leagues;
  final H2hRoundStore _rounds;
  final H2hSheetReader _sheets;
  final H2hSeatMoveStore _moves;
  final WeeklyLeagueProfileReader _profiles;
  final PushSender _sender;
  final IdGenerator _ids;
  final Clock _clock;

  /// The longest reason an admin may give.
  static const int maxReasonLength = 300;

  /// Candidates shown.
  static const int shownCandidates = 10;

  Future<Result<H2hAbsenceState?>> _state(DateTime now) => loadH2hAbsenceState(
    leagues: _leagues,
    rounds: _rounds,
    sheets: _sheets,
    moves: _moves,
    now: now,
  );

  /// The view for [principal].
  Future<Result<H2hAbsenceView>> view({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final now = _clock.nowUtc().toUtc();
    final stateResult = await _state(now);
    if (stateResult is Err<H2hAbsenceState?>) {
      return Result.err(stateResult.error);
    }
    final state = (stateResult as Ok<H2hAbsenceState?>).value;
    if (state == null) {
      return Result.ok(
        H2hAbsenceView(
          monthStart: H2hLeaguePolicy.monthStartOf(riyadhDayOf(now)),
          active: false,
          nextRound: null,
          relegatesAt: null,
          rounds: const [],
          watch: const [],
          candidates: const [],
          moves: const [],
          profiles: const {},
        ),
      );
    }

    final excusalsResult = await _moves.excusals(state.rounds);
    if (excusalsResult is Err<Map<H2hRoundId, H2hRoundExcusal>>) {
      return Result.err(excusalsResult.error);
    }
    final excusals =
        (excusalsResult as Ok<Map<H2hRoundId, H2hRoundExcusal>>).value;
    final warningsResult = await _moves.warningsOf(state.rounds);
    if (warningsResult
        is Err<List<({H2hRoundId roundId, UserId userId, DateTime at})>>) {
      return Result.err(warningsResult.error);
    }
    final warned = <UserId>{
      for (final w
          in (warningsResult
                  as Ok<
                    List<({H2hRoundId roundId, UserId userId, DateTime at})>
                  >)
              .value)
        w.userId,
    };

    final countedById = <H2hRoundId, H2hCountedRound>{
      for (final c in state.counted) c.roundId: c,
    };
    final eliteUsers = {for (final s in state.elite) s.userId};
    final rounds = <H2hAbsenceRoundView>[
      for (final round in state.rounds)
        H2hAbsenceRoundView(
          round: round,
          counted: countedById.containsKey(round.id),
          excusal: excusals[round.id],
          absent: countedById[round.id] == null
              ? 0
              : eliteUsers
                    .where((u) => !countedById[round.id]!.present.contains(u))
                    .length,
        ),
    ];

    final watch =
        <H2hAbsenceWatch>[
          for (final seat in state.elite)
            if (H2hAbsencePolicy.absenceRun(
              seat.userId,
              state.counted,
            ).isNotEmpty)
              H2hAbsenceWatch(
                seat: seat,
                groupNumber: seat.groupIndex + 1,
                absentRounds: H2hAbsencePolicy.absenceRun(
                  seat.userId,
                  state.counted,
                ),
                warned: warned.contains(seat.userId),
              ),
        ]..sort((a, b) {
          final byRun = b.absentRounds.length.compareTo(a.absentRounds.length);
          if (byRun != 0) {
            return byRun;
          }
          final byGroup = a.seat.groupIndex.compareTo(b.seat.groupIndex);
          return byGroup != 0 ? byGroup : a.seat.slot.compareTo(b.seat.slot);
        });

    final factsResult = await loadH2hCandidateFacts(
      state: state,
      moves: _moves,
      fallbackDay: state.nextRound?.day ?? now,
    );
    if (factsResult is Err<List<H2hCandidateFacts>>) {
      return Result.err(factsResult.error);
    }
    final ranked = H2hAbsencePolicy.rankCandidates(
      facts: (factsResult as Ok<List<H2hCandidateFacts>>).value,
      counted: state.counted,
      excluded: {...state.relegated, ...state.promoted},
    );
    final seatOf = {for (final s in state.extra) s.userId: s};
    final candidates = <H2hAbsenceCandidate>[
      for (final f in ranked.take(shownCandidates))
        if (seatOf[f.userId] != null)
          H2hAbsenceCandidate(
            seat: seatOf[f.userId]!,
            groupNumber:
                H2hLeaguePolicy.eliteGroups + seatOf[f.userId]!.groupIndex + 1,
            facts: f,
          ),
    ];

    DateTime? relegatesAt;
    final next = state.nextRound;
    if (next != null &&
        next.number >= 2 &&
        next.number <= H2hAbsencePolicy.lastEffectiveRound) {
      final day = await _rounds.dayFixtures(next.day);
      if (day is Ok<H2hDayFixtures> && day.value.firstKickoff != null) {
        relegatesAt = day.value.firstKickoff!.subtract(
          H2hAbsencePolicy.relegationLead,
        );
      }
    }

    final ids = <UserId>{
      for (final w in watch) w.seat.userId,
      for (final c in candidates) c.seat.userId,
      for (final m in state.moves) ...[m.outUser, m.inUser, ?m.decidedBy],
    };
    final profilesResult = await _profiles.profilesOf(ids.toList());
    if (profilesResult is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profilesResult.error);
    }

    return Result.ok(
      H2hAbsenceView(
        monthStart: state.monthStart,
        active: true,
        nextRound: next,
        relegatesAt: relegatesAt,
        rounds: List<H2hAbsenceRoundView>.unmodifiable(rounds),
        watch: List<H2hAbsenceWatch>.unmodifiable(watch),
        candidates: List<H2hAbsenceCandidate>.unmodifiable(candidates),
        moves: state.moves,
        profiles: (profilesResult as Ok<Map<UserId, WeeklyLeagueMemberProfile>>)
            .value,
        groupNumbers: {
          for (final g in state.book.groups)
            g.leagueId: H2hLeaguePolicy.groupNumberOf(
              division: g.division,
              groupIndex: g.groupIndex,
            ),
        },
      ),
    );
  }

  /// [principal] relegates [userId] by hand for [reason].
  Future<Result<H2hSeatMove>> relegate({
    required AuthenticatedUser principal,
    required UserId userId,
    required String reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final trimmed = reason.trim();
    if (trimmed.isEmpty || trimmed.length > maxReasonLength) {
      return const Result.err(
        AppError.validation(
          'h2h.reason_required',
          'A reason of 1 to 300 characters is required',
        ),
      );
    }
    final now = _clock.nowUtc().toUtc();
    final stateResult = await _state(now);
    if (stateResult is Err<H2hAbsenceState?>) {
      return Result.err(stateResult.error);
    }
    final state = (stateResult as Ok<H2hAbsenceState?>).value;
    if (state == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.absence_inactive',
          'This month has no elite groups to relegate from',
        ),
      );
    }
    H2hHeldSeat? seat;
    for (final s in state.elite) {
      if (s.userId == userId) {
        seat = s;
        break;
      }
    }
    if (state.relegated.contains(userId)) {
      return const Result.err(
        AppError.invariant(
          'h2h.already_relegated',
          'The player was relegated this month already',
        ),
      );
    }
    if (seat == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.not_elite_player',
          'The player holds no seat of the elite groups',
        ),
      );
    }
    final next = state.nextRound;
    if (next == null ||
        next.number < 2 ||
        next.number > H2hAbsencePolicy.lastEffectiveRound) {
      return const Result.err(
        AppError.invariant(
          'h2h.no_next_round',
          'No round from 2 to 19 is approved and not started yet',
        ),
      );
    }
    final factsResult = await loadH2hCandidateFacts(
      state: state,
      moves: _moves,
      fallbackDay: next.day,
    );
    if (factsResult is Err<List<H2hCandidateFacts>>) {
      return Result.err(factsResult.error);
    }
    final chosen = H2hAbsencePolicy.chooseSubstitute(
      out: userId,
      extra: state.extra,
      counted: state.counted,
      facts: (factsResult as Ok<List<H2hCandidateFacts>>).value,
      excluded: {...state.relegated, ...state.promoted},
      wouldRepeat: (out, extraSeat) =>
          state.wouldRepeat(out, extraSeat, next.number),
    );
    if (chosen == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.no_substitute',
          'No player of the extra groups qualifies as a substitute',
        ),
      );
    }
    final move = H2hSeatMove(
      id: _ids.newUuid(),
      monthStart: state.monthStart,
      fromRound: next.number,
      kind: H2hSeatMoveKind.admin,
      outUser: userId,
      inUser: chosen.$1.userId,
      eliteLeagueId: seat.leagueId,
      eliteSlot: seat.slot,
      extraLeagueId: chosen.$2.leagueId,
      extraSlot: chosen.$2.slot,
      absentRounds: [
        for (final r in H2hAbsencePolicy.absenceRun(userId, state.counted))
          (month: r.monthStart, round: r.number),
      ],
      facts: chosen.$1,
      reason: trimmed,
      decidedBy: principal.userId,
      createdAt: now,
    );
    final stored = await _moves.recordMove(move: move, logId: _ids.newUuid());
    if (stored is Err<void>) {
      return Result.err(stored.error);
    }
    await tellH2hSeatMove(
      state: state,
      move: move,
      moves: _moves,
      sender: _sender,
    );
    return Result.ok(move);
  }

  /// [principal] takes round [roundId] out of the absence count for
  /// [reason]. True when it changed.
  Future<Result<bool>> excuse({
    required AuthenticatedUser principal,
    required H2hRoundId roundId,
    required String reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final trimmed = reason.trim();
    if (trimmed.isEmpty || trimmed.length > maxReasonLength) {
      return const Result.err(
        AppError.validation(
          'h2h.reason_required',
          'A reason of 1 to 300 characters is required',
        ),
      );
    }
    final now = _clock.nowUtc().toUtc();
    final month = H2hLeaguePolicy.monthStartOf(riyadhDayOf(now));
    H2hRound? round;
    for (final m in [H2hLeaguePolicy.previousMonthOf(month), month]) {
      final roundsResult = await _rounds.roundsOf(m);
      if (roundsResult is Err<List<H2hRound>>) {
        return Result.err(roundsResult.error);
      }
      for (final r in (roundsResult as Ok<List<H2hRound>>).value) {
        if (r.id == roundId) {
          round = r;
        }
      }
    }
    if (round == null) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_unknown',
          'No round of this month or the month before has this id',
        ),
      );
    }
    if (!round.locked) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_not_started',
          'A round is excused once it has started',
        ),
      );
    }
    return _moves.excuse(
      roundId: roundId,
      reason: trimmed,
      by: principal.userId,
      logId: _ids.newUuid(),
    );
  }
}
