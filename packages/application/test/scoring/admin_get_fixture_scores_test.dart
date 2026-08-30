import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart';
import 'fake_fixture_score_repository.dart';

const _fixtureId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _participant = '44444444-4444-4444-4444-444444444444';

void main() {
  late FakeFixtureScoreRepository scores;
  late AdminGetFixtureScores useCase;

  setUp(() {
    scores = FakeFixtureScoreRepository();
    useCase = AdminGetFixtureScores(fixtureScoreRepository: scores);
  });

  test('refuses a non-admin caller before any read', () async {
    final result = await useCase(
      principal: principal(userId: adminUuid, role: PlatformRole.user),
      fixtureId: _fixtureId,
    );
    final error = (result as Err<List<ParticipantFixtureScore>>).error;
    expect(error.kind, ErrorKind.authorization);
    expect(error.code, 'auth.insufficient_role');
  });

  test('rejects a malformed fixture id', () async {
    final result = await useCase(
      principal: principal(userId: adminUuid),
      fixtureId: 'not-a-uuid',
    );
    final error = (result as Err<List<ParticipantFixtureScore>>).error;
    expect(error.kind, ErrorKind.validation);
    expect(error.code, 'competition.fixture_ref_malformed');
  });

  test(
    'an unscored fixture returns an empty list (live/partial, no gate)',
    () async {
      final result = await useCase(
        principal: principal(userId: adminUuid),
        fixtureId: _fixtureId,
      );
      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      expect((result as Ok<List<ParticipantFixtureScore>>).value, isEmpty);
    },
  );

  test('an admin reads scores regardless of the admin having no season '
      'membership of their own', () async {
    final fixtureRef =
        (FixtureRef.tryParse(_fixtureId) as Ok<FixtureRef>).value;
    await scores.saveFixtureScores([
      ParticipantFixtureScore.fromStored(
        fixture: fixtureRef,
        participantId:
            (ParticipantId.tryParse(_participant) as Ok<ParticipantId>).value,
        rulesetVersion: 1,
        result: FixtureScoreResult(
          fixture: fixtureRef,
          grade: FixtureScoreGrade.exactScoreline,
          points: 3,
        ),
      ),
    ]);

    final result = await useCase(
      principal: principal(userId: adminUuid),
      fixtureId: _fixtureId,
    );

    final list = (result as Ok<List<ParticipantFixtureScore>>).value;
    expect(list, hasLength(1));
    expect(list.single.points, 3);
  });
}
