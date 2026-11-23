import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AuthApi.myH2hCup', () {
    test('200 -> Ok(MyH2hCupDto), GET /me/h2h-cup', () async {
      const expected = MyH2hCupDto(
        state: 'qualified',
        monthStart: '2026-11-01',
        place: 1,
        groupNumber: 2,
        entrants: [
          H2hCupPlayerDto(
            userId: 'u-me',
            displayName: 'سامي',
            groupNumber: 2,
            isMe: true,
          ),
        ],
        stages: [
          H2hCupStageDto(
            round: 'semi',
            cupDay: 1,
            expectedDay: 20,
            phase: 'scheduled',
            attempt: 1,
            day: '2026-11-22',
            fixtureCount: 8,
            pairs: [
              H2hCupPairDto(
                slot: 1,
                home: H2hCupPlayerDto(
                  userId: 'u-me',
                  displayName: 'سامي',
                  groupNumber: 2,
                  isMe: true,
                ),
                away: H2hCupPlayerDto(
                  userId: 'u-x',
                  displayName: 'نورة',
                  groupNumber: 3,
                  isMe: false,
                ),
                isMine: true,
                decided: false,
              ),
            ],
          ),
        ],
      );
      final ctx = buildTransport(
        (_) async => okJson(expected.toJson()),
        token: 'jwt-abc',
      );

      final result = await AuthApi(ctx.transport).myH2hCup();

      expect((result as Ok<MyH2hCupDto>).value.toJson(), expected.toJson());
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/me/h2h-cup');
      expect(req.headers['authorization'], 'Bearer jwt-abc');
    });

    test('a missing key reads as the neutral value, never a crash', () {
      final dto = MyH2hCupDto.fromJson(const <String, Object?>{});

      expect(dto.state, 'not_qualified');
      expect(dto.stages, isEmpty);
      expect(dto.title, isNull);
    });

    test('a refusal arrives as an error with its code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(409, 'h2h.cup_unknown', 'no'),
      );

      final result = await AuthApi(ctx.transport).myH2hCup();

      expect((result as Err<MyH2hCupDto>).error.code, 'h2h.cup_unknown');
    });
  });
}
