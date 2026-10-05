import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('DuelPlayersDto round-trips its players', () {
    const dto = DuelPlayersDto(
      players: [DuelPlayerDto(userId: 'u-1', displayName: 'Badr')],
    );

    final back = DuelPlayersDto.fromJson(dto.toJson());

    expect(back.schemaVersion, 1);
    expect(back.players.single.userId, 'u-1');
    expect(back.players.single.displayName, 'Badr');
  });

  test('missing keys read as an empty answer', () {
    final dto = DuelPlayersDto.fromJson(const <String, Object?>{});
    expect(dto.players, isEmpty);
    expect(DuelPlayerDto.fromJson(const {}).displayName, '');
  });
}
