import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a relative
// import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/rounds/[id]/lock/index.dart' as route;
import 'competition_route_harness.dart';

/// Route tests for `POST /rounds/{id}/lock`. There was previously no
/// route-level test for this handler; added alongside the sequential-round
/// gate fix (product decision, 2026-08-14) because locking a round is exactly
/// the event that flips a LATER round's `RoundDto.isPredictable` from `false`
/// to `true`, which is the behavior this suite exists to pin down.
///
/// Tested through the real wiring (`context.read<Future<CompositionRoot>>()` →
/// `root.lockRound()`) over the in-memory [InMemoryCompetitionRepository],
/// mirroring `rounds_browse_test.dart` / `season_rounds_test.dart`.
void main() {
  final seasonId = (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value;

  RulesetSnapshot snapshot() =>
      (RulesetSnapshot.create(payload: const {'points': 1}, rulesetVersion: 1)
              as Ok<RulesetSnapshot>)
          .value;

  Round roundIn(String id, int sequence, RoundStatus status) =>
      Round.fromStored(
        id: (RoundId.tryParse(id) as Ok<RoundId>).value,
        seasonId: seasonId,
        sequence: sequence,
        predictionDeadline: DateTime.utc(2026, 8, sequence, 12),
        status: status,
        ruleset: snapshot(),
      );

  group('POST /rounds/{id}/lock', () {
    late InMemoryCompetitionRepository repo;

    CompositionRoot rootWith() {
      repo = InMemoryCompetitionRepository();
      return CompositionRoot.forTesting(
        lockRound: LockRound(repo),
        // The route re-fetches the season's rounds after locking, to compute
        // the response's own `isPredictable` (trivially false for a locked
        // round, but the mapper always requires the sibling context).
        listSeasonRounds: ListSeasonRounds(repository: repo),
      );
    }

    test('locks an open round and returns 200 with status locked, '
        'is_predictable false (a locked round is never predictable)', () async {
      final root = rootWith();
      repo.rounds[kRoundId] = roundIn(kRoundId, 1, RoundStatus.open);

      final context = wireContext(root: root, principal: adminPrincipal());

      final response = await route.onRequest(context, kRoundId);

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['status'], 'locked');
      expect(body['is_predictable'], isFalse);
    });

    test('locking round 1 flips round 2 predictable on its NEXT read — this is '
        'the exact unblock the sequential-round gate depends on', () async {
      final root = rootWith();
      repo.rounds[kRoundId] = roundIn(kRoundId, 1, RoundStatus.open);
      repo.rounds[kRoundId2] = roundIn(kRoundId2, 2, RoundStatus.open);

      // Sanity: before locking, round 2 is genuinely blocked.
      final before = await ListSeasonRounds(
        repository: repo,
      ).call(principal: adminPrincipal(), seasonId: kSeasonId);
      final beforeRounds = (before as Ok<List<Round>>).value;
      final round2Before = beforeRounds.firstWhere(
        (r) => r.id.value == kRoundId2,
      );
      expect(isRoundPredictable(round2Before, beforeRounds), isFalse);

      final context = wireContext(root: root, principal: adminPrincipal());
      final response = await route.onRequest(context, kRoundId);
      expect(response.statusCode, HttpStatus.ok);

      final after = await ListSeasonRounds(
        repository: repo,
      ).call(principal: adminPrincipal(), seasonId: kSeasonId);
      final afterRounds = (after as Ok<List<Round>>).value;
      final round2After = afterRounds.firstWhere(
        (r) => r.id.value == kRoundId2,
      );
      expect(isRoundPredictable(round2After, afterRounds), isTrue);
    });

    test(
      'locking an already-locked round is a 409 transition conflict',
      () async {
        final root = rootWith();
        repo.rounds[kRoundId] = roundIn(kRoundId, 1, RoundStatus.locked);

        final context = wireContext(root: root, principal: adminPrincipal());
        final response = await route.onRequest(context, kRoundId);

        expect(response.statusCode, HttpStatus.conflict);
        final body = await decodeBody(response);
        expect(body['code'], 'competition.round_illegal_transition');
      },
    );

    test('an unknown round id surfaces as 409 round_not_found', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
      );

      final response = await route.onRequest(
        context,
        '55555555-5555-5555-5555-555555555555',
      );

      expect(response.statusCode, HttpStatus.conflict);
      final body = await decodeBody(response);
      expect(body['code'], 'competition.round_not_found');
    });

    test('a non-admin principal is rejected with 401', () async {
      final root = rootWith();
      repo.rounds[kRoundId] = roundIn(kRoundId, 1, RoundStatus.open);

      final context = wireContext(root: root, principal: userPrincipal());
      final response = await route.onRequest(context, kRoundId);

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('an unsupported method (GET) is 405', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      );

      final response = await route.onRequest(context, kRoundId);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
