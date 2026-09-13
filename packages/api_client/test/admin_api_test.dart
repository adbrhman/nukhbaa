import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test(
    'adminGetUserPredictionHistory scopes the request to one user',
    () async {
      const user = UserSummaryDto(
        id: '11111111-1111-4111-8111-111111111111',
        email: 'user@example.com',
        displayName: 'علي علامي',
        status: 'active',
      );
      final dto = AdminUserPredictionHistoryDto(
        user: user,
        predictionCount: 1,
        exactCount: 1,
        correctDoubleCount: 1,
        totalPoints: 6,
        predictions: [
          const AdminUserPredictionRowDto(
            predictionId: '99999999-9999-4999-8999-999999999999',
            fixtureId: '77777777-7777-4777-8777-777777777777',
            kickoffAt: '2026-09-13T18:00:00Z',
            leagueName: 'الدوري الإيطالي',
            leagueLogoUrl: null,
            homeTeam: 'يوفنتوس',
            awayTeam: 'ميلان',
            predictedHomeGoals: 2,
            predictedAwayGoals: 1,
            finalHomeGoals: 2,
            finalAwayGoals: 1,
            grade: 'exact_scoreline',
            isDouble: true,
            points: 6,
          ),
        ],
      );

      final ctx = buildTransport((request) async => okJson(dto.toJson()));
      final result = await AdminApi(ctx.transport)
          .adminGetUserPredictionHistory(
            user.id,
            fromUtc: DateTime.utc(2026, 9, 13),
            toUtc: DateTime.utc(2026, 9, 14),
          );

      expect(result, Result<AdminUserPredictionHistoryDto>.ok(dto));
      expect(
        ctx.captured.single.url.path,
        '/admin/users/${user.id}/fixture-predictions',
      );
      expect(ctx.captured.single.url.queryParameters['from'], isNotNull);
      expect(ctx.captured.single.url.queryParameters['to'], isNotNull);
      expect(ctx.captured.single.method, 'GET');
    },
  );
}
