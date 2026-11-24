import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AdminApi.ownerH2hCup', () {
    test('200 -> Ok(OwnerH2hCupDto), GET /owner/h2h-cup?month=', () async {
      const expected = OwnerH2hCupDto(
        monthStart: '2026-11-01',
        months: [OwnerH2hCupMonthDto(monthStart: '2026-11-01', hasCup: true)],
        rounds: [
          OwnerH2hCupRoundDto(
            number: 1,
            day: '2026-11-03',
            fixtureCount: 8,
            locked: true,
            bySystem: true,
          ),
        ],
        paths: [
          OwnerH2hCupPathDto(
            place: 1,
            entrants: [
              H2hCupPlayerDto(
                userId: 'u-a',
                displayName: 'سامي',
                groupNumber: 1,
                isMe: false,
              ),
            ],
            stages: [
              H2hCupStageDto(
                round: 'semi',
                cupDay: 1,
                expectedDay: 20,
                phase: 'waiting',
                attempt: 1,
                pairs: [],
              ),
            ],
          ),
        ],
      );
      final ctx = buildTransport(
        (_) async => okJson(expected.toJson()),
        token: 'jwt-abc',
      );

      final result = await AdminApi(
        ctx.transport,
      ).ownerH2hCup(month: '2026-11-01');

      expect((result as Ok<OwnerH2hCupDto>).value.toJson(), expected.toJson());
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/owner/h2h-cup');
      expect(req.url.queryParameters['month'], '2026-11-01');
      expect(req.headers['authorization'], 'Bearer jwt-abc');
    });

    test('without a month no query is sent', () async {
      final ctx = buildTransport(
        (_) async => okJson(
          const OwnerH2hCupDto(
            monthStart: '2026-11-01',
            months: [],
            rounds: [],
            paths: [],
          ).toJson(),
        ),
      );

      await AdminApi(ctx.transport).ownerH2hCup();

      expect(ctx.captured.single.url.queryParameters, isEmpty);
    });

    test('a refusal arrives as an error with its code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(400, 'owner.h2h_month_invalid', 'no'),
      );

      final result = await AdminApi(ctx.transport).ownerH2hCup(month: 'x');

      expect(
        (result as Err<OwnerH2hCupDto>).error.code,
        'owner.h2h_month_invalid',
      );
    });
  });

  // NK314_04
  group('AdminApi.ownerH2hCupPicks', () {
    test(
      '200 -> Ok(H2hCupBoardDto), GET /owner/h2h-cup/picks?month=',
      () async {
        const expected = H2hCupBoardDto(
          monthStart: '2026-11-01',
          paths: [
            H2hCupBoardPathDto(
              place: 1,
              stages: [
                H2hCupBoardStageDto(
                  round: 'semi',
                  cupDay: 1,
                  phase: 'scheduled',
                  attempt: 1,
                  day: '2026-11-22',
                  pairs: [
                    H2hCupBoardPairDto(
                      slot: 1,
                      home: H2hCupPlayerDto(
                        userId: 'u-me',
                        displayName: 'X',
                        groupNumber: 2,
                        isMe: true,
                      ),
                      away: H2hCupPlayerDto(
                        userId: 'u-x',
                        displayName: 'Y',
                        groupNumber: 3,
                        isMe: false,
                      ),
                      decided: false,
                      fixtures: [
                        H2hCupBoardFixtureDto(
                          fixtureId: 'f-1',
                          homeTeam: 'A',
                          awayTeam: 'B',
                          state: 'not_started',
                          homeSide: H2hCupBoardSideDto(
                            revealed: true,
                            pick: H2hPickDto(
                              homeGoals: 2,
                              awayGoals: 1,
                              isDouble: false,
                            ),
                          ),
                          awaySide: H2hCupBoardSideDto.hidden(),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final ctx = buildTransport(
          (_) async => okJson(expected.toJson()),
          token: 'jwt-abc',
        );

        final result = await AdminApi(
          ctx.transport,
        ).ownerH2hCupPicks(month: '2026-11-01');

        expect(
          (result as Ok<H2hCupBoardDto>).value.toJson(),
          expected.toJson(),
        );
        final req = ctx.captured.single;
        expect(req.method, 'GET');
        expect(req.url.path, '/owner/h2h-cup/picks');
        expect(req.url.queryParameters['month'], '2026-11-01');
        expect(req.headers['authorization'], 'Bearer jwt-abc');
      },
    );

    test('without a month no query is sent', () async {
      final ctx = buildTransport(
        (_) async => okJson(const H2hCupBoardDto().toJson()),
      );

      await AdminApi(ctx.transport).ownerH2hCupPicks();

      expect(ctx.captured.single.url.queryParameters, isEmpty);
    });

    test('a refusal arrives as an error with its code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(400, 'owner.h2h_month_invalid', 'no'),
      );

      final result = await AdminApi(ctx.transport).ownerH2hCupPicks(month: 'x');

      expect(
        (result as Err<H2hCupBoardDto>).error.code,
        'owner.h2h_month_invalid',
      );
    });
  });
}
