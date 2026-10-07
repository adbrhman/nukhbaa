/// Hidden and test fixtures (migration 0098) through the real use-cases: the
/// feed, a prediction, scoring, the player's own list and the admin command
/// that hides and shows.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryAuditLogRepository;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import '../scoring/fake_fixture_score_repository.dart';
import '../scoring/fakes.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _player = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _admin = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _competition = 'aaaaaaaa-0000-0000-0000-000000000001';
const _season = 'aaaaaaaa-0000-0000-0000-000000000011';
const _playerParticipant = 'aaaaaaaa-0000-0000-0000-0000000000a1';
const _adminParticipant = 'aaaaaaaa-0000-0000-0000-0000000000a2';

const _real = 'ffffffff-0000-0000-0000-0000000000f1';
const _hidden = 'ffffffff-0000-0000-0000-0000000000f2';
const _test = 'ffffffff-0000-0000-0000-0000000000f3';

final _now = DateTime.utc(2026, 10, 10, 12);
final _kickoff = DateTime.utc(2026, 10, 10, 18);

FixtureSchedule _schedule(
  String id, {
  bool isTest = false,
  DateTime? hiddenAt,
}) => FixtureSchedule.fromStored(
  fixture: FixtureRef(id),
  homeTeam: 'Home $id',
  awayTeam: 'Away $id',
  kickoffAt: _kickoff,
  isTest: isTest,
  hiddenAt: hiddenAt,
);

SeasonFixture _link(String fixtureId, int order) =>
    (SeasonFixture.create(
              seasonId: const SeasonId(_season),
              fixture: FixtureRef(fixtureId),
              displayOrder: order,
            )
            as Ok<SeasonFixture>)
        .value;

FixturePrediction _prediction(
  String id,
  String fixtureId,
  String participant,
) =>
    (FixturePrediction.submit(
              id: PredictionId(id),
              fixture: FixtureRef(fixtureId),
              participantId: ParticipantId(participant),
              lock:
                  (FixtureLock.at(kickoffAt: _kickoff, nowUtc: _now)
                          as Ok<FixtureLock>)
                      .value,
              homeGoals: 1,
              awayGoals: 0,
              isDouble: false,
            )
            as Ok<FixturePrediction>)
        .value;

void main() {
  late FakeFixturePredictionRepository predictions;
  late FakeFixtureScheduleRepository schedules;
  late FakeCompetitionRepository competitions;

  setUp(() {
    predictions = FakeFixturePredictionRepository()
      ..seedSeasonFixture(_link(_real, 0))
      ..seedSeasonFixture(_link(_hidden, 1))
      ..seedSeasonFixture(_link(_test, 2));
    schedules = FakeFixtureScheduleRepository()
      ..seed(_schedule(_real))
      ..seed(_schedule(_hidden, hiddenAt: DateTime.utc(2026, 10, 9)))
      ..seed(_schedule(_test, isTest: true));
    competitions = FakeCompetitionRepository()
      ..seedCompetition(
        (Competition.create(
                  id: const CompetitionId(_competition),
                  name: 'Monthly',
                  format: FormatType.footballScoreline,
                  visibility: CompetitionVisibility.public,
                )
                as Ok<Competition>)
            .value,
      )
      ..seedSeason(
        (CompetitionSeason.create(
                  id: const SeasonId(_season),
                  competitionId: const CompetitionId(_competition),
                  label: '10/2026',
                  startAt: DateTime.utc(2026, 9, 30, 21),
                  endAt: DateTime.utc(2026, 10, 31, 21),
                )
                as Ok<CompetitionSeason>)
            .value,
      )
      ..seedParticipant(
        Participant.fromStored(
          id: const ParticipantId(_playerParticipant),
          seasonId: const SeasonId(_season),
          userId: const UserId(_player),
          status: ParticipantStatus.active,
          joinedAt: DateTime.utc(2026, 10),
        ),
      )
      ..seedParticipant(
        Participant.fromStored(
          id: const ParticipantId(_adminParticipant),
          seasonId: const SeasonId(_season),
          userId: const UserId(_admin),
          status: ParticipantStatus.active,
          joinedAt: DateTime.utc(2026, 10),
        ),
      );
  });

  group('the current-month feed', () {
    Future<List<CurrentMonthFixtureEntry>> feed(AuthenticatedUser who) async {
      final result = await ListCurrentMonthFixtures(
        competitionRepository: competitions,
        fixturePredictionRepository: predictions,
        fixtureScheduleRepository: schedules,
        clock: FixedClock(_now),
      )(principal: who);
      return (result as Ok<List<CurrentMonthFixtureEntry>>).value;
    }

    test('a player sees neither the hidden nor the test fixture', () async {
      final entries = await feed(userPrincipal(_player));
      expect(entries.map((e) => e.fixture.fixtureId.value), [_real]);
    });

    test('an admin sees the test fixture, flagged, and not the hidden '
        'one', () async {
      final entries = await feed(adminPrincipal(_admin));
      expect(entries.map((e) => e.fixture.fixtureId.value), [_real, _test]);
      expect(entries.last.fixture.isTest, isTrue);
      expect(entries.first.fixture.isTest, isFalse);
    });
  });

  group('a prediction', () {
    Future<Result<FixturePredictionView>> submit(
      AuthenticatedUser who,
      String fixtureId,
    ) =>
        SubmitFixturePrediction(
          fixturePredictionRepository: predictions,
          competitionRepository: competitions,
          fixtureScheduleRepository: schedules,
          idGenerator: FakeIdGenerator([
            '66666666-6666-6666-6666-666666666666',
          ]),
          clock: FixedClock(_now),
        )(
          principal: who,
          seasonId: _season,
          fixtureId: fixtureId,
          homeGoals: 2,
          awayGoals: 1,
        );

    test('nobody predicts a hidden fixture', () async {
      for (final who in [userPrincipal(_player), adminPrincipal(_admin)]) {
        final result = await submit(who, _hidden);
        expect(
          (result as Err<FixturePredictionView>).error.code,
          'prediction.fixture_unavailable',
        );
      }
      expect(predictions.count, 0);
    });

    test('a player cannot predict a test fixture; an admin can', () async {
      final refused = await submit(userPrincipal(_player), _test);
      expect(
        (refused as Err<FixturePredictionView>).error.code,
        'prediction.fixture_unavailable',
      );

      final accepted = await submit(adminPrincipal(_admin), _test);
      expect(accepted, isA<Ok<FixturePredictionView>>());
      expect(predictions.count, 1);
    });

    test('a real fixture is predicted as before', () async {
      final result = await submit(userPrincipal(_player), _real);
      expect(result, isA<Ok<FixturePredictionView>>());
    });
  });

  group('scoring', () {
    late FakeFixtureResultRepository results;
    late FakeFixtureScoreRepository scores;

    setUp(() {
      results = FakeFixtureResultRepository();
      scores = FakeFixtureScoreRepository();
      final fixtures = [_real, _hidden, _test];
      for (var i = 0; i < fixtures.length; i++) {
        final fixture = fixtures[i];
        predictions.seedPrediction(
          _prediction(
            '7777777$i-7777-7777-7777-777777777777',
            fixture,
            _adminParticipant,
          ),
          _now,
        );
        results.seed(
          FixtureResult.fromStored(
            fixture: FixtureRef(fixture),
            homeGoals: 1,
            awayGoals: 0,
          ),
        );
      }
    });

    Future<List<ParticipantFixtureScore>> score(String fixtureId) async {
      final result = await ScoreFixture(
        fixturePredictionRepository: predictions,
        resultRepository: results,
        scoreRepository: scores,
        rulesetProvider: FakeRulesetProvider(Result.ok(scoringSnapshot())),
        fixtureScheduleRepository: schedules,
      )(principal: adminPrincipal(_admin), fixtureId: fixtureId);
      return (result as Ok<List<ParticipantFixtureScore>>).value;
    }

    test(
      'a hidden or test fixture is not scored, and nothing is saved',
      () async {
        expect(await score(_hidden), isEmpty);
        expect(await score(_test), isEmpty);
        expect(scores.count, 0);
      },
    );

    test('a real fixture is scored as before', () async {
      expect(await score(_real), hasLength(1));
      expect(scores.count, 1);
    });
  });

  group("the player's own predictions", () {
    test('a prediction on a hidden fixture waits out of sight', () async {
      predictions
        ..seedParticipantOwner(
          const ParticipantId(_playerParticipant),
          const UserId(_player),
        )
        ..seedPrediction(
          _prediction(
            '88888881-8888-8888-8888-888888888888',
            _real,
            _playerParticipant,
          ),
          _now,
        )
        ..seedPrediction(
          _prediction(
            '88888882-8888-8888-8888-888888888888',
            _hidden,
            _playerParticipant,
          ),
          _now,
        );

      final result = await ListMyFixturePredictions(
        fixturePredictionRepository: predictions,
        fixtureScheduleRepository: schedules,
      )(principal: userPrincipal(_player));

      final views = (result as Ok<List<FixturePredictionView>>).value;
      expect(views.map((v) => v.prediction.fixture.value), [_real]);
    });
  });

  group('AdminSetFixturesHidden', () {
    late _Store store;
    late InMemoryAuditLogRepository audit;
    late AdminSetFixturesHidden command;

    setUp(() {
      store = _Store();
      audit = InMemoryAuditLogRepository();
      command = AdminSetFixturesHidden(
        store: store,
        auditRecorder: AuditRecorder(
          auditLog: audit,
          idGenerator: FakeIdGenerator([
            '99999991-9999-9999-9999-999999999999',
            '99999992-9999-9999-9999-999999999999',
          ]),
          clock: FixedClock(_now),
        ),
      );
    });

    test('hides each named fixture once and audits each change', () async {
      store.hidden.add(_hidden);

      final result = await command(
        principal: adminPrincipal(_admin),
        fixtureIds: [_real, _hidden, _real, _test],
        hidden: true,
      );

      final changed = (result as Ok<List<FixtureRef>>).value;
      expect(changed.map((f) => f.value), [_real, _test]);
      expect(store.asked, [_real, _hidden, _test]);
      expect(audit.rows.map((e) => e.targetRef), [_real, _test]);
      expect(audit.rows.map((e) => e.action).toSet(), {
        AuditAction.fixtureHidden,
      });
    });

    test('showing is audited as shown', () async {
      store.hidden.add(_hidden);

      await command(
        principal: adminPrincipal(_admin),
        fixtureIds: [_hidden],
        hidden: false,
      );

      expect(store.hidden, isEmpty);
      expect(audit.rows.single.action, AuditAction.fixtureShown);
    });

    test('refuses a player, a missing flag, no ids and a bad id', () async {
      final player = await command(
        principal: userPrincipal(_player),
        fixtureIds: [_real],
        hidden: true,
      );
      expect(
        (player as Err<List<FixtureRef>>).error.kind,
        ErrorKind.authorization,
      );

      final noFlag = await command(
        principal: adminPrincipal(_admin),
        fixtureIds: [_real],
        hidden: null,
      );
      expect(
        (noFlag as Err<List<FixtureRef>>).error.code,
        'competition.fixture_visibility_missing',
      );

      final none = await command(
        principal: adminPrincipal(_admin),
        fixtureIds: const [],
        hidden: true,
      );
      expect(
        (none as Err<List<FixtureRef>>).error.code,
        'competition.fixture_ids_invalid',
      );

      final bad = await command(
        principal: adminPrincipal(_admin),
        fixtureIds: ['not-a-uuid'],
        hidden: true,
      );
      expect(
        (bad as Err<List<FixtureRef>>).error.code,
        'competition.fixture_ref_malformed',
      );

      expect(store.asked, isEmpty);
      expect(audit.rows, isEmpty);
    });
  });
}

/// The visibility column as a set of hidden ids.
final class _Store implements FixtureVisibilityStore {
  final Set<String> hidden = {};
  final List<String> asked = [];

  @override
  Future<Result<List<FixtureRef>>> setHidden(
    List<FixtureRef> fixtures, {
    required bool hidden,
  }) async {
    asked.addAll(fixtures.map((f) => f.value));
    final changed = <FixtureRef>[];
    for (final f in fixtures) {
      final bool now = this.hidden.contains(f.value);
      if (now == hidden) continue;
      if (hidden) {
        this.hidden.add(f.value);
      } else {
        this.hidden.remove(f.value);
      }
      changed.add(f);
    }
    return Result.ok(changed);
  }
}
