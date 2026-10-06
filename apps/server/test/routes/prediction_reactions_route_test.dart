import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/[fixtureId]/predictions/[participantId]/reaction/index.dart'
    as reaction_route;
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/[fixtureId]/reactions/index.dart'
    as reactions_route;
import 'competition_route_harness.dart';

/// Route tests for reactions on a prediction (migration 0094) through the
/// real wiring: the predictions' own kickoff gate, a first reaction that
/// tells the owner, a change that does not, no reaction to one's own
/// prediction, the board's tallies, and taking a reaction back.
void main() {
  const fixtureId = '66666666-6666-6666-6666-666666666666';
  const myParticipant = '99999999-9999-9999-9999-999999999999';
  const otherParticipant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const otherUser = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  final kickoff = DateTime.utc(2026, 10, 6, 18);

  FixtureRef fixture() =>
      (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value;

  Participant participant(String id, String userId) => Participant.fromStored(
    id: (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
    seasonId: (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
    userId: (UserId.tryParse(userId) as Ok<UserId>).value,
    status: ParticipantStatus.active,
    joinedAt: DateTime.utc(2026, 9),
  );

  ({CompositionRoot root, InMemoryNotificationRepository inbox}) build({
    required DateTime now,
  }) {
    final competition = InMemoryCompetitionRepository();
    final me = participant(myParticipant, kUserId);
    final other = participant(otherParticipant, otherUser);
    competition.participants.add(me);
    final names = InMemoryParticipantReader()
      ..add(me)
      ..add(other);
    final schedules = InMemoryFixtureScheduleRepository()
      ..seed(
        FixtureSchedule.fromStored(
          fixture: fixture(),
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
          kickoffAt: kickoff,
        ),
      );
    final predictions = _InMemoryFixturePredictionRepository()
      ..links.add(
        (SeasonFixture.create(
                  seasonId:
                      (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
                  fixture: fixture(),
                  displayOrder: 0,
                )
                as Ok<SeasonFixture>)
            .value,
      );
    for (final id in [myParticipant, otherParticipant]) {
      predictions.stored.add(
        FixturePredictionView(
          prediction: FixturePrediction.fromStored(
            id: (PredictionId.tryParse(id) as Ok<PredictionId>).value,
            fixture: fixture(),
            participantId:
                (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
            homeGoals: 1,
            awayGoals: 0,
          ),
          submittedAt: DateTime.utc(2026, 10, 6, 12),
        ),
      );
    }
    final clock = FixedClock(now);
    final reveal = ListFixturePredictions(
      competitionRepository: competition,
      fixturePredictionRepository: predictions,
      fixtureScheduleRepository: schedules,
      participantReader: names,
      clock: clock,
    );
    final reactions = _MemoryReactions({
      myParticipant: kUserId,
      otherParticipant: otherUser,
    });
    final inbox = InMemoryNotificationRepository();
    final root = CompositionRoot.forTesting(
      listPredictionReactions: ListPredictionReactions(
        reveal: reveal,
        reactions: reactions,
      ),
      reactToPrediction: ReactToPrediction(
        reveal: reveal,
        competition: competition,
        reactions: reactions,
        notify: CreateNotification(
          notifications: inbox,
          idGenerator: ScriptedIdGenerator([
            'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1',
            'd2d2d2d2-d2d2-4d2d-8d2d-d2d2d2d2d2d2',
          ]),
          clock: clock,
        ),
        idGenerator: ScriptedIdGenerator([
          'e1e1e1e1-e1e1-4e1e-8e1e-e1e1e1e1e1e1',
          'e2e2e2e2-e2e2-4e2e-8e2e-e2e2e2e2e2e2',
        ]),
        clock: clock,
      ),
      removePredictionReaction: RemovePredictionReaction(
        reveal: reveal,
        reactions: reactions,
      ),
    );
    return (root: root, inbox: inbox);
  }

  Future<Response> react(
    CompositionRoot root, {
    String target = otherParticipant,
    Object? body = const {'emoji': 'fire'},
    HttpMethod method = HttpMethod.put,
  }) => reaction_route.onRequest(
    wireContext(
      root: root,
      principal: userPrincipal(),
      method: method,
      body: body,
    ),
    kSeasonId,
    fixtureId,
    target,
  );

  Future<Response> board(CompositionRoot root) => reactions_route.onRequest(
    wireContext(root: root, principal: userPrincipal(), method: HttpMethod.get),
    kSeasonId,
    fixtureId,
  );

  final after = kickoff.add(const Duration(minutes: 5));

  test('a first reaction tells the owner; a change does not', () async {
    final setup = build(now: after);

    final first = await react(setup.root);
    final change = await react(setup.root, body: const {'emoji': 'clap'});

    expect(first.statusCode, HttpStatus.ok);
    expect((await decodeBody(first))['first'], isTrue);
    expect(change.statusCode, HttpStatus.ok);
    expect((await decodeBody(change))['first'], isFalse);
    final told = setup.inbox.notifications
        .where((n) => n.recipientId.value == otherUser)
        .toList();
    expect(told, hasLength(1));
    expect(told.single.kind, NotificationKind.predictionReaction);
  });

  test('the board reads each prediction tally with my own', () async {
    final setup = build(now: after);
    await react(setup.root);

    final response = await board(setup.root);

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    final rows = (body['reactions']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(rows, hasLength(1));
    expect(rows.single['participant_id'], otherParticipant);
    expect(rows.single['counts'], {'fire': 1});
    expect(rows.single['mine'], 'fire');
  });

  test('my own prediction cannot be reacted to (409)', () async {
    final setup = build(now: after);

    final response = await react(setup.root, target: myParticipant);

    expect(response.statusCode, HttpStatus.conflict);
    expect(
      (await decodeBody(response))['code'],
      'social.prediction_reaction_self',
    );
  });

  test('before kickoff both routes refuse (409)', () async {
    final setup = build(now: kickoff.subtract(const Duration(minutes: 1)));

    final put = await react(setup.root);
    final get = await board(setup.root);

    expect(put.statusCode, HttpStatus.conflict);
    expect(get.statusCode, HttpStatus.conflict);
    expect((await decodeBody(get))['code'], 'prediction.fixture_not_started');
  });

  test('a body without an emoji is 400', () async {
    final setup = build(now: after);

    final response = await react(setup.root, body: <String, Object?>{});

    expect(response.statusCode, HttpStatus.badRequest);
  });

  test('DELETE takes the reaction back', () async {
    final setup = build(now: after);
    await react(setup.root);

    final removed = await react(setup.root, method: HttpMethod.delete);
    final again = await react(setup.root, method: HttpMethod.delete);

    expect((await decodeBody(removed))['removed'], isTrue);
    expect((await decodeBody(again))['removed'], isFalse);
  });

  test('any other method is 405', () async {
    final setup = build(now: after);

    final post = await react(setup.root, method: HttpMethod.post);
    final put = await reactions_route.onRequest(
      wireContext(
        root: setup.root,
        principal: userPrincipal(),
        method: HttpMethod.put,
      ),
      kSeasonId,
      fixtureId,
    );

    expect(post.statusCode, HttpStatus.methodNotAllowed);
    expect(put.statusCode, HttpStatus.methodNotAllowed);
  });
}

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

final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final List<SeasonFixture> links = [];
  final List<FixturePredictionView> stored = [];

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    for (final link in links) {
      if (link.seasonId == seasonId && link.fixture == fixture) {
        return Result.ok(link);
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async =>
      const Result.ok(null);

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async => const Result.ok(false);

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async => Result.ok([
    for (final view in stored)
      if (view.prediction.fixture == fixture) view,
  ]);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(
    SeasonId seasonId,
  ) async => const Result.ok(<FixtureRef>[]);

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async =>
      const Result.ok(<FixturePredictionView>[]);
}
