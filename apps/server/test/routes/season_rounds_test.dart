import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/seasons/[id]/rounds/index.dart' as route;
import 'competition_route_harness.dart';

void main() {
  group('POST /seasons/{id}/rounds', () {
    late InMemoryCompetitionRepository repo;

    CompositionRoot rootWith({bool withSeason = true}) {
      repo = InMemoryCompetitionRepository();
      final compId =
          (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>).value;
      final seasonId = (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value;
      repo.competitions[kCompetitionId] = Competition.fromStored(
        id: compId,
        name: 'Comp',
        format: FormatType.footballScoreline,
        visibility: CompetitionVisibility.public,
      );
      if (withSeason) {
        repo.seasons[kSeasonId] = CompetitionSeason.fromStored(
          id: seasonId,
          competitionId: compId,
          label: '2026/27',
        );
      }
      return CompositionRoot.forTesting(
        openRound: OpenRound(
          repository: repo,
          rulesetProvider: const FixedRulesetProvider(),
          idGenerator: ScriptedIdGenerator([kRoundId]),
        ),
        // The route fetches the season's rounds after opening one, to compute
        // `RoundDto.isPredictable` (the sequential-round gate).
        listSeasonRounds: ListSeasonRounds(repository: repo),
      );
    }

    test('opens a round with a frozen ruleset and returns 201', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        body: const {
          'sequence': 1,
          'prediction_deadline': '2026-08-01T12:00:00Z',
        },
      );

      final response = await route.onRequest(context, kSeasonId);

      expect(response.statusCode, HttpStatus.created);
      final body = await decodeBody(response);
      expect(body['id'], kRoundId);
      expect(body['season_id'], kSeasonId);
      expect(body['sequence'], 1);
      expect(body['status'], 'open');
      expect(body['ruleset_version'], 1);
      // The DTO deliberately never leaks the opaque ruleset payload.
      expect(body.containsKey('ruleset_snapshot'), isFalse);
      // Sequence 1, no earlier sibling round: predictable as soon as opened.
      expect(body['is_predictable'], isTrue);
    });

    test(
      'opening round 2 while round 1 is still open reports it as NOT yet '
      'predictable — the sequential-round gate (the bug this fix closes: a '
      'season used to open all its rounds up front with no ordering)',
      () async {
        final repo0 = InMemoryCompetitionRepository();
        final compId =
            (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>).value;
        final seasonId = (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value;
        repo0.competitions[kCompetitionId] = Competition.fromStored(
          id: compId,
          name: 'Comp',
          format: FormatType.footballScoreline,
          visibility: CompetitionVisibility.public,
        );
        repo0.seasons[kSeasonId] = CompetitionSeason.fromStored(
          id: seasonId,
          competitionId: compId,
          label: '2026/27',
        );
        // Round 1 already open (predicted separately, still in progress).
        repo0.rounds[kRoundId2] = Round.fromStored(
          id: (RoundId.tryParse(kRoundId2) as Ok<RoundId>).value,
          seasonId: seasonId,
          sequence: 1,
          predictionDeadline: DateTime.utc(2026, 8, 1, 12),
          status: RoundStatus.open,
          ruleset:
              (RulesetSnapshot.create(
                        payload: const {'points': 1},
                        rulesetVersion: 1,
                      )
                      as Ok<RulesetSnapshot>)
                  .value,
        );
        final root = CompositionRoot.forTesting(
          openRound: OpenRound(
            repository: repo0,
            rulesetProvider: const FixedRulesetProvider(),
            idGenerator: ScriptedIdGenerator([kRoundId]),
          ),
          listSeasonRounds: ListSeasonRounds(repository: repo0),
        );

        final context = wireContext(
          root: root,
          principal: adminPrincipal(),
          body: const {
            'sequence': 2,
            'prediction_deadline': '2026-08-08T12:00:00Z',
          },
        );

        final response = await route.onRequest(context, kSeasonId);

        expect(response.statusCode, HttpStatus.created);
        final body = await decodeBody(response);
        expect(body['sequence'], 2);
        expect(body['status'], 'open');
        // Open, but round 1 hasn't locked yet — not predictable.
        expect(body['is_predictable'], isFalse);
      },
    );

    test('a malformed deadline is 400 validation', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        body: const {'sequence': 1, 'prediction_deadline': 'not-a-date'},
      );

      final response = await route.onRequest(context, kSeasonId);

      expect(response.statusCode, HttpStatus.badRequest);
      final body = await decodeBody(response);
      expect(body['code'], 'request.deadline_malformed');
    });

    test('an absent deadline field is 400', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        body: const {'sequence': 1},
      );

      final response = await route.onRequest(context, kSeasonId);

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('a missing season surfaces as 409 season_not_found', () async {
      final context = wireContext(
        root: rootWith(withSeason: false),
        principal: adminPrincipal(),
        body: const {
          'sequence': 1,
          'prediction_deadline': '2026-08-01T12:00:00Z',
        },
      );

      final response = await route.onRequest(context, kSeasonId);

      expect(response.statusCode, HttpStatus.conflict);
      final body = await decodeBody(response);
      expect(body['code'], 'competition.season_not_found');
    });

    test('a non-admin principal is rejected with 401', () async {
      final context = wireContext(
        root: rootWith(),
        principal: userPrincipal(),
        body: const {
          'sequence': 1,
          'prediction_deadline': '2026-08-01T12:00:00Z',
        },
      );

      final response = await route.onRequest(context, kSeasonId);

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });
}
