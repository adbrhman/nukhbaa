import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('closed goes over the wire, and an older payload is not closed', () {
    final closed = MatchDetailsDto.fromJson(
      const MatchDetailsDto(
        fixtureId: 'f-1',
        available: false,
        closed: true,
      ).toJson(),
    );
    expect(closed.closed, isTrue);
    expect(closed.available, isFalse);

    final older = MatchDetailsDto.fromJson(const <String, Object?>{
      'schema_version': 1,
      'fixture_id': 'f-1',
      'available': false,
    });
    expect(older.closed, isFalse);
  });
}
