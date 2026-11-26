import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

// NK340_02
/// Script 340: the owners' own audit log survives the wire unchanged.
void main() {
  final OwnerAuditLogDto dto = OwnerAuditLogDto(
    entries: [
      OwnerAuditEntryDto(
        source: 'admin',
        id: 7,
        actorName: 'المالك',
        method: 'PATCH',
        path: '/admin/fixtures/f-1/result',
        at: DateTime.utc(2026, 11, 26, 12, 30),
        target: 'الهلال × النصر',
        result: '2-1',
      ),
      OwnerAuditEntryDto(
        source: 'owner',
        id: 7,
        actorName: 'المالك',
        method: 'POST',
        path: '/owner/switches',
        at: DateTime.utc(2026, 11, 26, 12),
      ),
    ],
  );

  test('both sources round-trip through JSON, ids kept apart by source', () {
    final Map<String, Object?> json = dto.toJson();

    final OwnerAuditLogDto back = OwnerAuditLogDto.fromJson(json);

    expect(back, dto);
    expect(back.hashCode, dto.hashCode);
    expect(back.entries.map((e) => e.source), ['admin', 'owner']);
    expect(back.entries.map((e) => e.id), [7, 7]);
    expect(back.entries.first, isNot(back.entries.last));
  });

  test('the wire keys are snake_case and absent details stay null', () {
    final Map<String, Object?> json = dto.toJson();
    final List<Object?> lines = json['entries']! as List<Object?>;
    final Map<String, Object?> owner = lines.last! as Map<String, Object?>;

    expect(json['schema_version'], 1);
    expect(owner['actor_name'], 'المالك');
    expect(owner['at'], '2026-11-26T12:00:00.000Z');
    expect(owner['target'], isNull);
    expect(owner['result'], isNull);
    expect(OwnerAuditEntryDto.fromJson(owner).target, isNull);
  });

  test('a payload without a schema version reads as version 1', () {
    final OwnerAuditLogDto back = OwnerAuditLogDto.fromJson({
      'entries': <Object?>[],
    });

    expect(back.schemaVersion, 1);
    expect(back.entries, isEmpty);
  });

  test('a time sent with an offset comes back in UTC', () {
    final OwnerAuditEntryDto line = OwnerAuditEntryDto.fromJson({
      'source': 'owner',
      'id': 1,
      'actor_name': 'x',
      'method': 'DELETE',
      'path': '/owner/x',
      'at': '2026-11-26T15:00:00+03:00',
    });

    expect(line.at, DateTime.utc(2026, 11, 26, 12));
    expect(line.at.isUtc, isTrue);
  });
}
