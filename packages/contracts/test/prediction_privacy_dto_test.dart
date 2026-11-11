import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Script 261: what the admins read of predictions survives the wire.
void main() {
  const UserSummaryDto user = UserSummaryDto(
    id: '11111111-1111-4111-8111-111111111111',
    status: 'active',
    email: 'k@t.io',
    displayName: 'خالد',
  );

  test('a history says how many predictions are sealed', () {
    const AdminUserPredictionHistoryDto dto = AdminUserPredictionHistoryDto(
      user: user,
      predictionCount: 0,
      exactCount: 0,
      correctDoubleCount: 0,
      totalPoints: 0,
      predictions: <AdminUserPredictionRowDto>[],
      sealedCount: 3,
    );

    final Map<String, Object?> json = dto.toJson();

    expect(json['sealed_count'], 3);
    expect(AdminUserPredictionHistoryDto.fromJson(json), dto);
  });

  test('a server before script 261 sends no count: nothing sealed', () {
    final Map<String, Object?> json = const AdminUserPredictionHistoryDto(
      user: user,
      predictionCount: 0,
      exactCount: 0,
      correctDoubleCount: 0,
      totalPoints: 0,
      predictions: <AdminUserPredictionRowDto>[],
    ).toJson()..remove('sealed_count');

    expect(AdminUserPredictionHistoryDto.fromJson(json).sealedCount, 0);
  });

  test("support's reading round-trips with its notice", () {
    const SupportPredictionsPeekDto dto = SupportPredictionsPeekDto(
      predictions: <SupportPeekedPredictionDto>[
        SupportPeekedPredictionDto(
          fixtureId: 'aaaaaaaa-0000-4000-8000-000000000001',
          homeTeam: 'الهلال',
          awayTeam: 'النصر',
          kickoffAt: '2026-11-12T18:00:00.000Z',
          homeGoals: 2,
          awayGoals: 1,
          isDouble: true,
          leagueName: 'دوري روشن',
        ),
        SupportPeekedPredictionDto(
          fixtureId: 'aaaaaaaa-0000-4000-8000-000000000002',
          homeTeam: 'الأهلي',
          awayTeam: 'الاتحاد',
          kickoffAt: '2026-11-13T18:00:00.000Z',
          homeGoals: 0,
          awayGoals: 0,
          isDouble: false,
        ),
      ],
      notice: SupportMessageDto(
        id: 7,
        sender: 'support',
        body: 'اطّلع فريق الدعم على توقعاتك',
        createdAt: '2026-11-12T15:00:00.000Z',
      ),
    );

    final Map<String, Object?> json = dto.toJson();
    final SupportPredictionsPeekDto back = SupportPredictionsPeekDto.fromJson(
      json,
    );

    expect(back.predictions, dto.predictions);
    expect(back.notice.body, 'اطّلع فريق الدعم على توقعاتك');
    expect(back.notice.sender, 'support');
    expect(back.schemaVersion, 1);
    final Map<String, Object?> second =
        (json['predictions']! as List<Object?>)[1]! as Map<String, Object?>;
    expect(second.containsKey('league_name'), isFalse);
  });
}
