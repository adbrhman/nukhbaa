import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('PredictionReactionsDto round-trips through JSON', () {
    const dto = PredictionReactionsDto(
      reactions: [
        PredictionReactionTallyDto(
          participantId: 'p1',
          counts: {'fire': 2, 'clap': 1},
          mine: 'fire',
        ),
        PredictionReactionTallyDto(participantId: 'p2', counts: {'sad': 1}),
      ],
    );

    final back = PredictionReactionsDto.fromJson(dto.toJson());

    expect(back.reactions, hasLength(2));
    expect(back.of('p1')!.counts, {'fire': 2, 'clap': 1});
    expect(back.of('p1')!.mine, 'fire');
    expect(back.of('p1')!.total, 3);
    expect(back.of('p2')!.mine, isNull);
    expect(back.of('p3'), isNull);
    expect(dto.toJson()['schema_version'], 1);
  });

  test('a malformed answer reads as no reactions, never a guess', () {
    final dto = PredictionReactionsDto.fromJson(const {
      'reactions': [
        'not a map',
        {
          'participant_id': 'p1',
          'counts': {'fire': 'two', 'clap': 1},
        },
      ],
    });

    expect(dto.reactions.single.counts, {'clap': 1});
    expect(PredictionReactionsDto.fromJson(const {}).reactions, isEmpty);
  });

  test('the kinds are the closed set the server accepts', () {
    expect(predictionReactionKinds, [
      'like',
      'fire',
      'clap',
      'laugh',
      'sad',
      'shock',
    ]);
  });
}
