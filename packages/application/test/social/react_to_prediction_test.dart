import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart' show FixedClock, userPrincipal;
import '../ledger/fakes.dart' show FakeParticipantReader;
import '../notification/fakes.dart'
    show FakeIdGenerator, InMemoryNotificationRepository;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import '../scoring/fakes.dart' show scoringParticipant;

const _season = '11111111-1111-1111-1111-111111111111';
const _fixture = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _meUser = '22222222-2222-2222-2222-222222222222';
const _outsiderUser = '33333333-3333-3333-3333-333333333333';
const _meParticipant = '44444444-4444-4444-4444-444444444444';
const _otherParticipant = '55555555-5555-5555-5555-555555555555';
const _otherUser = '66666666-6666-6666-6666-666666666666';
const _silentParticipant = '77777777-7777-7777-7777-777777777777';

final DateTime _kickoff = DateTime.utc(2026, 10, 6, 18);

FixtureRef _ref() => (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value;

/// Reactions in memory, keyed by (prediction owner, reacting player).
final class _MemoryReactions implements PredictionReactionRepository {
  _MemoryReactions(this._owners);

  final Map<String, String> _owners;
  final Map<(String, String), ReactionKind> live = {};

  @override
  Future<Result<PredictionReactionWrite>> upsert({
    required String id,
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
    required ReactionKind kind,
    required DateTime reactedAt,
  }) async {
    final key = (target.value, reactor.value);
    final inserted = !live.containsKey(key);
    live[key] = kind;
    return Result.ok(
      PredictionReactionWrite(
        inserted: inserted,
        targetUserId: UserId(_owners[target.value]!),
      ),
    );
  }

  @override
  Future<Result<bool>> remove({
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
  }) async => Result.ok(live.remove((target.value, reactor.value)) != null);

  @override
  Future<Result<List<PredictionReactionTally>>> tallies({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required UserId viewer,
  }) async {
    final Map<String, Map<ReactionKind, int>> counts = {};
    final Map<String, ReactionKind> mine = {};
    live.forEach(((String, String) key, ReactionKind kind) {
      final byKind = counts.putIfAbsent(key.$1, () => {});
      byKind[kind] = (byKind[kind] ?? 0) + 1;
      if (key.$2 == viewer.value) mine[key.$1] = kind;
    });
    return Result.ok([
      for (final e in counts.entries)
        PredictionReactionTally(
          targetParticipantId:
              (ParticipantId.tryParse(e.key) as Ok<ParticipantId>).value,
          counts: e.value,
          mine: mine[e.key],
        ),
    ]);
  }
}

typedef _Harness = ({
  ReactToPrediction react,
  ListPredictionReactions list,
  RemovePredictionReaction remove,
  _MemoryReactions reactions,
  InMemoryNotificationRepository inbox,
});

_Harness _harness({required DateTime now}) {
  final competition = FakeCompetitionRepository();
  final predictions = FakeFixturePredictionRepository();
  final schedules = FakeFixtureScheduleRepository();
  final participants = FakeParticipantReader();
  final me = scoringParticipant(
    id: _meParticipant,
    seasonId: _season,
    userId: _meUser,
  );
  final other = scoringParticipant(
    id: _otherParticipant,
    seasonId: _season,
    userId: _otherUser,
  );
  competition.seedParticipant(me);
  participants
    ..seed(me)
    ..seed(other);
  predictions.seedSeasonFixture(
    (SeasonFixture.create(
              seasonId: (SeasonId.tryParse(_season) as Ok<SeasonId>).value,
              fixture: _ref(),
              displayOrder: 0,
            )
            as Ok<SeasonFixture>)
        .value,
  );
  schedules.seed(
    FixtureSchedule.fromStored(
      fixture: _ref(),
      homeTeam: 'Arsenal',
      awayTeam: 'Chelsea',
      kickoffAt: _kickoff,
    ),
  );
  for (final (id, home, away) in [
    (_meParticipant, 2, 1),
    (_otherParticipant, 0, 3),
  ]) {
    predictions.seedPrediction(
      FixturePrediction.fromStored(
        id: (PredictionId.tryParse(id) as Ok<PredictionId>).value,
        fixture: _ref(),
        participantId: (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
        homeGoals: home,
        awayGoals: away,
      ),
      DateTime.utc(2026, 10, 6, 12),
    );
  }
  final clock = FixedClock(now);
  final reveal = ListFixturePredictions(
    competitionRepository: competition,
    fixturePredictionRepository: predictions,
    fixtureScheduleRepository: schedules,
    participantReader: participants,
    clock: clock,
  );
  final reactions = _MemoryReactions({
    _meParticipant: _meUser,
    _otherParticipant: _otherUser,
  });
  final inbox = InMemoryNotificationRepository();
  return (
    react: ReactToPrediction(
      reveal: reveal,
      competition: competition,
      reactions: reactions,
      notify: CreateNotification(
        notifications: inbox,
        idGenerator: FakeIdGenerator([
          'b1b1b1b1-b1b1-4b1b-8b1b-b1b1b1b1b1b1',
          'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2',
          'b3b3b3b3-b3b3-4b3b-8b3b-b3b3b3b3b3b3',
        ]),
        clock: clock,
      ),
      idGenerator: FakeIdGenerator(['c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1']),
      clock: clock,
    ),
    list: ListPredictionReactions(reveal: reveal, reactions: reactions),
    remove: RemovePredictionReaction(reveal: reveal, reactions: reactions),
    reactions: reactions,
    inbox: inbox,
  );
}

Future<Result<PredictionReactionWrite>> _react(
  _Harness h, {
  String target = _otherParticipant,
  String emoji = 'fire',
  String user = _meUser,
}) => h.react(
  principal: userPrincipal(user),
  seasonId: _season,
  fixtureId: _fixture,
  targetParticipantId: target,
  emoji: emoji,
);

Future<int> _unread(_Harness h, String user) async =>
    (await h.inbox.unreadCount(UserId(user)) as Ok<int>).value;

void main() {
  final after = _kickoff.add(const Duration(minutes: 10));

  test('a first reaction is kept and tells the owner, once', () async {
    final h = _harness(now: after);

    final first = await _react(h);
    final changed = await _react(h, emoji: 'clap');

    expect((first as Ok<PredictionReactionWrite>).value.inserted, isTrue);
    expect((changed as Ok<PredictionReactionWrite>).value.inserted, isFalse);
    expect(h.reactions.live, {(_otherParticipant, _meUser): ReactionKind.clap});
    expect(await _unread(h, _otherUser), 1);
  });

  test('nobody reacts to their own prediction', () async {
    final h = _harness(now: after);

    final result = await _react(h, target: _meParticipant);

    expect(
      (result as Err<PredictionReactionWrite>).error.code,
      'social.prediction_reaction_self',
    );
    expect(h.reactions.live, isEmpty);
    expect(await _unread(h, _meUser), 0);
  });

  test('a player without a prediction has nothing to react to', () async {
    final h = _harness(now: after);

    final result = await _react(h, target: _silentParticipant);

    expect(
      (result as Err<PredictionReactionWrite>).error.code,
      'social.prediction_reaction_no_prediction',
    );
    expect(h.reactions.live, isEmpty);
  });

  test('before kickoff nothing can be reacted to', () async {
    final h = _harness(now: _kickoff.subtract(const Duration(minutes: 1)));

    final result = await _react(h);

    expect(
      (result as Err<PredictionReactionWrite>).error.code,
      'prediction.fixture_not_started',
    );
    expect(h.reactions.live, isEmpty);
  });

  test('only a member of the season reacts', () async {
    final h = _harness(now: after);

    final result = await _react(h, user: _outsiderUser);

    expect(
      (result as Err<PredictionReactionWrite>).error.code,
      'prediction.not_a_participant',
    );
  });

  test('an unknown reaction is refused', () async {
    final h = _harness(now: after);

    final result = await _react(h, emoji: 'heart');

    expect(
      (result as Err<PredictionReactionWrite>).error.code,
      'social.reaction_emoji_unknown',
    );
    expect(h.reactions.live, isEmpty);
  });

  test('the list counts each prediction and knows the caller own', () async {
    final h = _harness(now: after);
    await _react(h);

    final result = await h.list(
      principal: userPrincipal(_meUser),
      seasonId: _season,
      fixtureId: _fixture,
    );

    final tally = (result as Ok<List<PredictionReactionTally>>).value.single;
    expect(tally.targetParticipantId.value, _otherParticipant);
    expect(tally.counts, {ReactionKind.fire: 1});
    expect(tally.mine, ReactionKind.fire);
    expect(tally.total, 1);
  });

  test('the list stays closed before kickoff', () async {
    final h = _harness(now: _kickoff.subtract(const Duration(minutes: 1)));

    final result = await h.list(
      principal: userPrincipal(_meUser),
      seasonId: _season,
      fixtureId: _fixture,
    );

    expect(
      (result as Err<List<PredictionReactionTally>>).error.code,
      'prediction.fixture_not_started',
    );
  });

  test('a reaction can be taken back, once', () async {
    final h = _harness(now: after);
    await _react(h);

    Future<Result<bool>> takeBack() => h.remove(
      principal: userPrincipal(_meUser),
      seasonId: _season,
      fixtureId: _fixture,
      targetParticipantId: _otherParticipant,
    );

    expect((await takeBack() as Ok<bool>).value, isTrue);
    expect((await takeBack() as Ok<bool>).value, isFalse);
    expect(h.reactions.live, isEmpty);
  });
}
