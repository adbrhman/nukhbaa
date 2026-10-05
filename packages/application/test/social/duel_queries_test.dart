import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';

const _me = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _rival = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _season = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _fixture = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _challenge = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _duel = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

final DateTime _kickoff = DateTime.utc(2026, 10, 5, 18);
final DateTime _before = DateTime.utc(2026, 10, 5, 12);
final DateTime _after = DateTime.utc(2026, 10, 5, 19);

final class _Reader implements DuelReader {
  _Reader({
    this.byCode,
    this.challenges = const [],
    this.duels = const [],
    this.failure,
  });

  final DuelChallengePreview? byCode;
  final List<DuelChallengePreview> challenges;
  final List<DuelRecord> duels;
  final AppError? failure;

  String? askedCode;
  UserId? askedUser;
  DateTime? askedSince;

  @override
  Future<Result<DuelChallengePreview?>> findChallengeByCode(
    DuelCode code,
  ) async {
    askedCode = code.value;
    final error = failure;
    if (error != null) return Result.err(error);
    return Result.ok(byCode);
  }

  @override
  Future<Result<List<DuelChallengePreview>>> listOpenChallengesFor({
    required UserId userId,
    required DateTime now,
    required int limit,
  }) async {
    askedUser = userId;
    final error = failure;
    if (error != null) return Result.err(error);
    return Result.ok(challenges);
  }

  @override
  Future<Result<List<DuelRecord>>> listDuelsFor({
    required UserId userId,
    required DateTime since,
    required int limit,
  }) async {
    askedSince = since;
    final error = failure;
    if (error != null) return Result.err(error);
    return Result.ok(duels);
  }
}

DuelChallengePreview _preview({
  String challenger = _rival,
  String? target,
  int capacity = 5,
  int accepted = 0,
  DuelChallengeStatus status = DuelChallengeStatus.open,
}) => DuelChallengePreview(
  challengeId: const DuelChallengeId(_challenge),
  code: (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>).value,
  seasonId: const SeasonId(_season),
  fixture: const FixtureRef(_fixture),
  homeTeam: 'Home',
  awayTeam: 'Away',
  kickoffAt: _kickoff,
  challengerUserId: UserId(challenger),
  challengerName: 'Rival',
  targetUserId: target == null ? null : UserId(target),
  capacity: capacity,
  acceptedCount: accepted,
  status: status,
  createdAt: _before,
);

DuelRecord _record({DuelScore? mine, DuelScore? theirs}) => DuelRecord(
  duelId: const DuelId(_duel),
  challengeId: const DuelChallengeId(_challenge),
  fixture: const FixtureRef(_fixture),
  homeTeam: 'Home',
  awayTeam: 'Away',
  kickoffAt: _kickoff,
  acceptedAt: _before,
  callerIsChallenger: false,
  opponentUserId: const UserId(_rival),
  opponentName: 'Rival',
  myPick: const DuelPick(homeGoals: 2, awayGoals: 1, isDouble: true),
  opponentPick: const DuelPick(homeGoals: 0, awayGoals: 0, isDouble: false),
  myScore: mine,
  opponentScore: theirs,
);

Future<MyDuels> _list(_Reader reader, DateTime now) async {
  final result = await ListMyDuels(
    duels: reader,
    clock: FixedClock(now),
  ).call(principal: userPrincipal(_me));
  return (result as Ok<MyDuels>).value;
}

void main() {
  group('ListMyDuels', () {
    test('hides the opponent prediction before kickoff', () async {
      final mine = await _list(_Reader(duels: [_record()]), _before);
      final duel = mine.duels.single;
      expect(duel.state, DuelState.upcoming);
      expect(duel.record.opponentPick, isNull);
      expect(duel.record.myPick!.homeGoals, 2);
      expect(duel.outcome, isNull);
      expect(duel.myPoints, isNull);
    });

    test('shows it from kickoff, live until both grades are final', () async {
      final mine = await _list(
        _Reader(
          duels: [
            _record(
              mine: const DuelScore(grade: 'pending', points: 0),
              theirs: const DuelScore(grade: 'pending', points: 0),
            ),
          ],
        ),
        _after,
      );
      final duel = mine.duels.single;
      expect(duel.state, DuelState.live);
      expect(duel.record.opponentPick!.homeGoals, 0);
      expect(duel.outcome, isNull);
      expect(duel.opponentPoints, isNull);
    });

    test('a settled duel is won on official points, double included', () async {
      final mine = await _list(
        _Reader(
          duels: [
            _record(
              mine: const DuelScore(grade: 'exact_scoreline', points: 6),
              theirs: const DuelScore(grade: 'correct_outcome', points: 3),
            ),
          ],
        ),
        _after,
      );
      final duel = mine.duels.single;
      expect(duel.state, DuelState.settled);
      expect(duel.outcome, DuelOutcome.won);
      expect(duel.myPoints, 6);
      expect(duel.opponentPoints, 3);
    });

    test('equal points is a draw, fewer is a loss', () async {
      final draw = await _list(
        _Reader(
          duels: [
            _record(
              mine: const DuelScore(grade: 'incorrect', points: 0),
              theirs: const DuelScore(grade: 'incorrect', points: 0),
            ),
          ],
        ),
        _after,
      );
      expect(draw.duels.single.outcome, DuelOutcome.draw);

      final loss = await _list(
        _Reader(
          duels: [
            _record(
              mine: const DuelScore(grade: 'incorrect', points: 0),
              theirs: const DuelScore(grade: 'exact_scoreline', points: 3),
            ),
          ],
        ),
        _after,
      );
      expect(loss.duels.single.outcome, DuelOutcome.lost);
    });

    test('derives each challenge state and the caller role', () async {
      final mine = await _list(
        _Reader(
          challenges: [
            _preview(challenger: _me),
            _preview(target: _me, capacity: 1),
            _preview(capacity: 1, accepted: 1),
          ],
        ),
        _before,
      );
      expect(mine.challenges[0].state, DuelChallengeState.open);
      expect(mine.challenges[0].callerIsChallenger, isTrue);
      expect(mine.challenges[1].callerIsTarget, isTrue);
      expect(mine.challenges[1].callerIsChallenger, isFalse);
      expect(mine.challenges[2].state, DuelChallengeState.full);
    });

    test('asks for the caller and a bounded history', () async {
      final reader = _Reader();
      await _list(reader, _before);
      expect(reader.askedUser, const UserId(_me));
      expect(reader.askedSince, _before.subtract(ListMyDuels.history));
    });

    test('a reader failure passes through', () async {
      final result = await ListMyDuels(
        duels: _Reader(
          failure: const AppError.transient('db.query_failed', 'down'),
        ),
        clock: FixedClock(_before),
      ).call(principal: userPrincipal(_me));
      expect((result as Err<MyDuels>).error.code, 'db.query_failed');
    });
  });

  group('GetDuelChallengeByCode', () {
    Future<Result<DuelChallengeView>> open(
      _Reader reader,
      String code, {
      DateTime? now,
    }) => GetDuelChallengeByCode(
      duels: reader,
      clock: FixedClock(now ?? _before),
    ).call(principal: userPrincipal(_me), code: code);

    test('normalises the typed code and answers the open challenge', () async {
      final reader = _Reader(byCode: _preview(target: _me, capacity: 1));
      final result = await open(reader, ' abcdefghjkmn ');
      final view = (result as Ok<DuelChallengeView>).value;
      expect(reader.askedCode, 'ABCDEFGHJKMN');
      expect(view.state, DuelChallengeState.open);
      expect(view.callerIsTarget, isTrue);
    });

    test('a challenge past kickoff is expired', () async {
      final result = await open(
        _Reader(byCode: _preview()),
        'ABCDEFGHJKMN',
        now: _after,
      );
      expect(
        (result as Ok<DuelChallengeView>).value.state,
        DuelChallengeState.expired,
      );
    });

    test('a cancelled challenge stays cancelled', () async {
      final result = await open(
        _Reader(byCode: _preview(status: DuelChallengeStatus.cancelled)),
        'ABCDEFGHJKMN',
      );
      expect(
        (result as Ok<DuelChallengeView>).value.state,
        DuelChallengeState.cancelled,
      );
    });

    test('an unknown code is not found', () async {
      final result = await open(_Reader(), 'ABCDEFGHJKMN');
      expect(
        (result as Err<DuelChallengeView>).error.code,
        'social.duel_challenge_not_found',
      );
    });

    test('a malformed code never reaches the reader', () async {
      final reader = _Reader();
      final result = await open(reader, 'ABC');
      expect(
        (result as Err<DuelChallengeView>).error.code,
        'social.duel_code_malformed',
      );
      expect(reader.askedCode, isNull);
    });
  });
}
