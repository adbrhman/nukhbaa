/// Unit tests for [ScoreFixtureController] and [PostFixtureToLedgerController]
/// (Phase 7.10.x Step 2) — the per-fixture siblings of the retired
/// `ScoreRoundController` / `PostRoundToLedgerController`.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:shared/shared.dart';

import '../../support/admin_harness.dart';

const FixtureScoresDto _scores = FixtureScoresDto(
  fixtureId: 'f-1',
  scores: <ParticipantFixtureScoreDto>[
    ParticipantFixtureScoreDto(
      fixtureId: 'f-1',
      participantId: 'part-1',
      rulesetVersion: 1,
      grade: 'exact_scoreline',
      points: 6,
    ),
  ],
);

const PostFixtureToLedgerResponseDto _ledgerResponse =
    PostFixtureToLedgerResponseDto(
      fixtureId: 'f-1',
      appendedEntries: <FixturePointEntryDto>[
        FixturePointEntryDto(
          id: 'entry-1',
          participantId: 'part-1',
          fixtureId: 'f-1',
          kind: 'fixture_score',
          amount: 6,
          sourceRef: 'fixture-f-1',
          occurredAt: '2026-08-27T10:00:00.000Z',
        ),
      ],
    );

void main() {
  group('ScoreFixtureController', () {
    test('initial state is null, building it issues no request', () {
      final harness = buildAdminHarness(
        (_) async => okJsonObject(_scores.toJson()),
      );
      addTearDown(harness.dispose);

      expect(harness.container.read(scoreFixtureControllerProvider), isNull);
      expect(harness.captured, isEmpty);
    });

    test(
      'score success -> AsyncData, POSTs empty body to /fixtures/{id}/score',
      () async {
        final harness = buildAdminHarness(
          (_) async => okJsonObject(_scores.toJson()),
        );
        addTearDown(harness.dispose);

        await harness.container
            .read(scoreFixtureControllerProvider.notifier)
            .score('f-1', 's-1');

        final state = harness.container.read(scoreFixtureControllerProvider);
        expect(state, isA<AsyncData<FixtureScoresDto>>());
        expect((state! as AsyncData<FixtureScoresDto>).value, _scores);

        expect(harness.captured, hasLength(1));
        final request = harness.captured.single.request;
        expect(request.method, 'POST');
        expect(request.url.path, '/fixtures/f-1/score');
        expect(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
          isEmpty,
        );
      },
    );

    test('409 fixture_not_locked -> AsyncError(invariant)', () async {
      final harness = buildAdminHarness(
        (_) async => errorEnvelope(
          409,
          'scoring.fixture_not_locked',
          'not kicked off yet',
        ),
      );
      addTearDown(harness.dispose);

      await harness.container
          .read(scoreFixtureControllerProvider.notifier)
          .score('f-1', 's-1');

      final state = harness.container.read(scoreFixtureControllerProvider);
      expect(state, isA<AsyncError<FixtureScoresDto>>());
      final error = (state! as AsyncError<FixtureScoresDto>).error as AppError;
      expect(error.kind, ErrorKind.invariant);
      expect(error.code, 'scoring.fixture_not_locked');
    });

    test('re-scoring (idempotent) issues a fresh request each call', () async {
      var calls = 0;
      final harness = buildAdminHarness((_) async {
        calls++;
        return okJsonObject(_scores.toJson());
      });
      addTearDown(harness.dispose);

      final notifier = harness.container.read(
        scoreFixtureControllerProvider.notifier,
      );
      await notifier.score('f-1', 's-1');
      await notifier.score('f-1', 's-1');

      expect(calls, 2);
      expect(
        harness.container.read(scoreFixtureControllerProvider),
        isA<AsyncData<FixtureScoresDto>>(),
      );
    });
  });

  group('PostFixtureToLedgerController', () {
    test('initial state is null, building it issues no request', () {
      final harness = buildAdminHarness(
        (_) async => okJsonObject(_ledgerResponse.toJson()),
      );
      addTearDown(harness.dispose);

      expect(
        harness.container.read(postFixtureToLedgerControllerProvider),
        isNull,
      );
      expect(harness.captured, isEmpty);
    });

    test(
      'post success -> AsyncData, POSTs empty body to /fixtures/{id}/ledger',
      () async {
        final harness = buildAdminHarness(
          (_) async => okJsonObject(_ledgerResponse.toJson()),
        );
        addTearDown(harness.dispose);

        await harness.container
            .read(postFixtureToLedgerControllerProvider.notifier)
            .post('f-1', 's-1');

        final state = harness.container.read(
          postFixtureToLedgerControllerProvider,
        );
        expect(state, isA<AsyncData<PostFixtureToLedgerResponseDto>>());
        expect(
          (state! as AsyncData<PostFixtureToLedgerResponseDto>).value,
          _ledgerResponse,
        );

        expect(harness.captured, hasLength(1));
        final request = harness.captured.single.request;
        expect(request.method, 'POST');
        expect(request.url.path, '/fixtures/f-1/ledger');
        expect(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
          isEmpty,
        );
      },
    );

    test('409 fixture_not_scored -> AsyncError(invariant)', () async {
      final harness = buildAdminHarness(
        (_) async =>
            errorEnvelope(409, 'ledger.fixture_not_scored', 'score it first'),
      );
      addTearDown(harness.dispose);

      await harness.container
          .read(postFixtureToLedgerControllerProvider.notifier)
          .post('f-1', 's-1');

      final state = harness.container.read(
        postFixtureToLedgerControllerProvider,
      );
      expect(state, isA<AsyncError<PostFixtureToLedgerResponseDto>>());
      final error =
          (state! as AsyncError<PostFixtureToLedgerResponseDto>).error
              as AppError;
      expect(error.kind, ErrorKind.invariant);
      expect(error.code, 'ledger.fixture_not_scored');
    });

    test('idempotent replay -> AsyncData with empty appendedEntries', () async {
      const emptyReplay = PostFixtureToLedgerResponseDto(
        fixtureId: 'f-1',
        appendedEntries: <FixturePointEntryDto>[],
      );
      final harness = buildAdminHarness(
        (_) async => okJsonObject(emptyReplay.toJson()),
      );
      addTearDown(harness.dispose);

      await harness.container
          .read(postFixtureToLedgerControllerProvider.notifier)
          .post('f-1', 's-1');

      final state = harness.container.read(
        postFixtureToLedgerControllerProvider,
      );
      expect(
        (state! as AsyncData<PostFixtureToLedgerResponseDto>)
            .value
            .appendedEntries,
        isEmpty,
      );
    });
  });
}
