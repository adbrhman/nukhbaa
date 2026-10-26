import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('GroupInviteesDto round-trips its players', () {
    const dto = GroupInviteesDto(
      players: [GroupInviteeDto(userId: 'u-1', displayName: 'Badr')],
    );

    final back = GroupInviteesDto.fromJson(dto.toJson());

    expect(back.schemaVersion, 1);
    expect(back.players.single.userId, 'u-1');
    expect(back.players.single.displayName, 'Badr');
  });

  test('missing keys read as an empty answer', () {
    final dto = GroupInviteesDto.fromJson(const <String, Object?>{});
    expect(dto.players, isEmpty);
    expect(GroupInviteeDto.fromJson(const {}).displayName, '');
  });
}
