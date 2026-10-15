import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/me/fixture-scores.dart' as route;
import 'competition_route_harness.dart';

/// Route tests for `GET /me/fixture-scores` (script 75): real wiring
/// (`context.read<Future<CompositionRoot>>()` -> `root.listMyFixtureScores`
/// -> [ListMyFixtureScores]) over an in-memory [MyFixtureScoreReader].
final class _Reader implements MyFixtureScoreReader {
  _Reader(this.answer);

  final Result<List<MyFixtureScore>> answer;
  final List<UserId> asked = [];

  @override
  Future<Result<List<MyFixtureScore>>> listByUser(UserId userId) async {
    asked.add(userId);
    return answer;
  }
}

const _participant = '99999999-9999-9999-9999-999999999999';
const _scored = '66666666-6666-6666-6666-666666666666';
const _waiting = '77777777-7777-7777-7777-777777777777';

void main() {
  CompositionRoot rootWith(_Reader reader) => CompositionRoot.forTesting(
    listMyFixtureScores: ListMyFixtureScores(reader: reader),
  );

  group('GET /me/fixture-scores', () {
    test(
      "returns the caller's own rows, a waiting one without points",
      () async {
        final reader = _Reader(
          const Result.ok(<MyFixtureScore>[
            MyFixtureScore(
              participantId: ParticipantId(_participant),
              fixture: FixtureRef(_scored),
              grade: FixtureScoreGrade.exactScoreline,
              points: 6,
              result: FixtureResult.fromStored(
                fixture: FixtureRef(_scored),
                homeGoals: 2,
                awayGoals: 1,
              ),
            ),
            MyFixtureScore(
              participantId: ParticipantId(_participant),
              fixture: FixtureRef(_waiting),
              result: FixtureResult.fromStored(
                fixture: FixtureRef(_waiting),
                homeGoals: 0,
                awayGoals: 0,
              ),
            ),
          ]),
        );

        final response = await route.onRequest(
          wireContext(
            root: rootWith(reader),
            principal: userPrincipal(),
            method: HttpMethod.get,
          ),
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = await response.json() as List<Object?>;
        expect(body, <Object?>[
          <String, Object?>{
            'schema_version': 1,
            'participant_id': _participant,
            'fixture_id': _scored,
            'grade': 'exact_scoreline',
            'points': 6,
            'result_home_goals': 2,
            'result_away_goals': 1,
          },
          <String, Object?>{
            'schema_version': 1,
            'participant_id': _participant,
            'fixture_id': _waiting,
            'result_home_goals': 0,
            'result_away_goals': 0,
          },
        ]);
        expect(reader.asked, [userPrincipal().userId]);
      },
    );

    test('nothing scored or recorded yet is an empty array', () async {
      final response = await route.onRequest(
        wireContext(
          root: rootWith(_Reader(const Result.ok(<MyFixtureScore>[]))),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(await response.json(), isEmpty);
    });

    test('a slow database is a 503 the app may try again', () async {
      final response = await route.onRequest(
        wireContext(
          root: rootWith(
            _Reader(
              const Result.err(
                AppError.transient(
                  'db.query_timeout',
                  'Database query timed out',
                ),
              ),
            ),
          ),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      final body = await decodeBody(response);
      expect(body['code'], 'db.query_timeout');
    });

    test('405 on anything but GET', () async {
      final response = await route.onRequest(
        wireContext(
          root: rootWith(_Reader(const Result.ok(<MyFixtureScore>[]))),
          principal: userPrincipal(),
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
