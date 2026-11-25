import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// Script 261: support reads a player's open predictions from his
/// conversation, with a reason.
void main() {
  const String conversation = 'cccccccc-0000-4000-8000-000000000001';

  test(
    'peekSupportPredictions posts the reason and reads the answer',
    () async {
      const SupportPredictionsPeekDto dto = SupportPredictionsPeekDto(
        predictions: <SupportPeekedPredictionDto>[
          SupportPeekedPredictionDto(
            fixtureId: 'aaaaaaaa-0000-4000-8000-000000000002',
            homeTeam: 'الهلال',
            awayTeam: 'النصر',
            kickoffAt: '2026-11-12T18:00:00.000Z',
            homeGoals: 3,
            awayGoals: 0,
            isDouble: true,
          ),
        ],
        notice: SupportMessageDto(
          id: 9,
          sender: 'support',
          body: 'اطّلع فريق الدعم على توقعاتك',
          createdAt: '2026-11-12T15:00:00.000Z',
        ),
      );
      final ctx = buildTransport((request) async => okJson(dto.toJson()));

      final result = await AdminApi(
        ctx.transport,
      ).peekSupportPredictions(conversation, reason: 'توقعه لم يُحفظ');

      final read = (result as Ok<SupportPredictionsPeekDto>).value;
      expect(read.predictions, dto.predictions);
      expect(read.notice!.body, 'اطّلع فريق الدعم على توقعاتك');
      final sent = ctx.captured.single;
      expect(sent.method, 'POST');
      expect(
        sent.url.path,
        '/admin/support/conversations/$conversation/predictions',
      );
      expect(jsonDecode(sent.body), <String, Object?>{
        'reason': 'توقعه لم يُحفظ',
      });
    },
  );

  test('peekSupportPredictions reads an answer without a notice', () async {
    final ctx = buildTransport(
      (request) async => okJson(<String, Object?>{
        'schema_version': 1,
        'predictions': <Object?>[
          <String, Object?>{
            'fixture_id': 'aaaaaaaa-0000-4000-8000-000000000002',
            'home_team': 'HOME',
            'away_team': 'AWAY',
            'kickoff_at': '2026-11-12T18:00:00.000Z',
            'home_goals': 1,
            'away_goals': 1,
            'is_double': false,
          },
        ],
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).peekSupportPredictions(conversation, reason: 'owner check');

    final read = (result as Ok<SupportPredictionsPeekDto>).value;
    expect(read.notice, isNull);
    expect(read.predictions.single.homeTeam, 'HOME');
    expect(read.predictions.single.homeGoals, 1);
    expect(ctx.captured.single.method, 'POST');
    expect(
      ctx.captured.single.url.path,
      '/admin/support/conversations/$conversation/predictions',
    );
    expect(jsonDecode(ctx.captured.single.body), <String, Object?>{
      'reason': 'owner check',
    });
  });
}
