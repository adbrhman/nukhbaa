/// Unit tests for [FixturePredictionController] — the per-fixture submit
/// notifier (Axiom 4 Amendment).
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/fixture_prediction_controller.dart';
import 'package:mobile/features/fixture_prediction/fixture_prediction_submission.dart';
import 'package:shared/shared.dart';

import '../../support/prediction_harness.dart';

const FixturePredictionKey _key = (seasonId: 's-1', fixtureId: 'f-a');

const FixturePredictionDto _stored = FixturePredictionDto(
  id: 'fp-1',
  participantId: 'part-1',
  fixtureId: 'f-a',
  submittedAt: '2026-08-25T10:00:00.000Z',
  homeGoals: 2,
  awayGoals: 1,
);

FixtureSubmissionState _stateOf(PredictionHarness h) =>
    h.container.read(fixturePredictionControllerProvider(_key));

FixturePredictionController _controller(PredictionHarness h) =>
    h.container.read(fixturePredictionControllerProvider(_key).notifier);

void main() {
  group('FixturePredictionController — initial state', () {
    test('starts Idle, building it issues no request', () {
      final harness = buildPredictionHarness(
        (_) async => okJsonObject(_stored.toJson()),
      );
      addTearDown(harness.dispose);

      expect(_stateOf(harness), const FixtureSubmissionIdle());
      expect(harness.captured, isEmpty);
    });
  });

  group('FixturePredictionController.submit — success', () {
    test(
      'a valid submit -> InFlight then Succeeded, POSTing the exact command '
      'body to /seasons/{id}/fixtures/{fixtureId}/prediction',
      () async {
        final harness = buildPredictionHarness(
          (_) async => okJsonObject(_stored.toJson()),
        );
        addTearDown(harness.dispose);

        await _controller(
          harness,
        ).submit(homeGoals: 2, awayGoals: 1, isDouble: true);

        final state = _stateOf(harness);
        expect(state, isA<FixtureSubmissionSucceeded>());
        expect((state as FixtureSubmissionSucceeded).prediction, _stored);

        expect(harness.captured, hasLength(1));
        final request = harness.captured.single.request;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/seasons/${_key.seasonId}/fixtures/${_key.fixtureId}/prediction',
        );
        final body = FixturePredictionCommandDto.fromJson(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
        );
        expect(body.homeGoals, 2);
        expect(body.awayGoals, 1);
        expect(body.isDouble, isTrue);
      },
    );
  });

  group('FixturePredictionController.submit — auto-join retry', () {
    test(
      'not_a_participant -> joins the season -> retries submit -> Succeeded',
      () async {
        var submitCalls = 0;
        final harness = buildPredictionHarness((request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith('/prediction')) {
            submitCalls++;
            if (submitCalls == 1) {
              return errorEnvelope(
                409,
                'prediction.not_a_participant',
                'join first',
              );
            }
            return okJsonObject(_stored.toJson());
          }
          if (request.method == 'POST' &&
              request.url.path == '/seasons/${_key.seasonId}/participants') {
            return okJsonObject(const ParticipantDto(
              id: 'part-1',
              seasonId: 's-1',
              userId: 'u-1',
              status: 'active',
              joinedAt: '2026-08-25T09:00:00.000Z',
            ).toJson());
          }
          return errorEnvelope(404, 'not_found', 'unexpected request');
        });
        addTearDown(harness.dispose);

        await _controller(harness).submit(homeGoals: 1, awayGoals: 0);

        final state = _stateOf(harness);
        expect(state, isA<FixtureSubmissionSucceeded>());
        expect(submitCalls, 2, reason: 'submit, join, then retry the SAME submit');
      },
    );

    test('join itself failing surfaces the join error, not the original', () async {
      final harness = buildPredictionHarness((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/prediction')) {
          return errorEnvelope(409, 'prediction.not_a_participant', 'join first');
        }
        if (request.method == 'POST' &&
            request.url.path == '/seasons/${_key.seasonId}/participants') {
          return errorEnvelope(403, 'competition.join_closed', 'closed');
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await _controller(harness).submit(homeGoals: 1, awayGoals: 0);

      final state = _stateOf(harness);
      expect(state, isA<FixtureSubmissionFailed>());
      expect((state as FixtureSubmissionFailed).error.code, 'competition.join_closed');
    });
  });

  group('FixturePredictionController.submit — failure', () {
    test('409 fixture_locked -> Failed(invariant)', () async {
      final harness = buildPredictionHarness(
        (_) async => errorEnvelope(
          409,
          'prediction.fixture_locked',
          'already kicked off',
        ),
      );
      addTearDown(harness.dispose);

      await _controller(harness).submit(homeGoals: 1, awayGoals: 1);

      final state = _stateOf(harness);
      expect(state, isA<FixtureSubmissionFailed>());
      final error = (state as FixtureSubmissionFailed).error;
      expect(error.kind, ErrorKind.invariant);
      expect(error.code, 'prediction.fixture_locked');
    });

    test('transient/503 -> Failed(transient, retryable)', () async {
      final harness = buildPredictionHarness(
        (_) async => errorEnvelope(503, 'server.unavailable', 'down'),
      );
      addTearDown(harness.dispose);

      await _controller(harness).submit(homeGoals: 1, awayGoals: 1);

      final state = _stateOf(harness);
      expect(state, isA<FixtureSubmissionFailed>());
      final error = (state as FixtureSubmissionFailed).error;
      expect(error.kind, ErrorKind.transient);
      expect(error.isRetryable, isTrue);
    });
  });

  group('FixturePredictionController.submit — double-submit guard', () {
    test('a second submit while one is in flight is ignored (one request)', () async {
      final harness = buildPredictionHarness((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return okJsonObject(_stored.toJson());
      });
      addTearDown(harness.dispose);

      final first = _controller(harness).submit(homeGoals: 1, awayGoals: 0);
      final second = _controller(harness).submit(homeGoals: 9, awayGoals: 9);
      await Future.wait([first, second]);

      expect(harness.captured, hasLength(1));
    });
  });

  group('FixturePredictionController.reset', () {
    test('returns Idle after a failure', () async {
      final harness = buildPredictionHarness(
        (_) async => errorEnvelope(503, 'server.unavailable', 'down'),
      );
      addTearDown(harness.dispose);

      await _controller(harness).submit(homeGoals: 1, awayGoals: 1);
      expect(_stateOf(harness), isA<FixtureSubmissionFailed>());

      _controller(harness).reset();
      expect(_stateOf(harness), const FixtureSubmissionIdle());
    });

    test('is a no-op while InFlight', () async {
      final harness = buildPredictionHarness((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return okJsonObject(_stored.toJson());
      });
      addTearDown(harness.dispose);

      final pending = _controller(harness).submit(homeGoals: 1, awayGoals: 0);
      expect(_stateOf(harness), const FixtureSubmissionInFlight());
      _controller(harness).reset();
      expect(_stateOf(harness), const FixtureSubmissionInFlight());
      await pending;
    });
  });
}
