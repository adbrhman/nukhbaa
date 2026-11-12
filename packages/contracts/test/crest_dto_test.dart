import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Script 265: the crests survive the wire.
void main() {
  test('the manifest round-trips; a missing list is empty', () {
    const CrestManifestDto dto = CrestManifestDto(
      version: '0a1b2c3d',
      clubsEnabled: true,
      crests: <String, String>{'arsenal': 'https://x/clubs/arsenal.1.png'},
    );

    final CrestManifestDto back = CrestManifestDto.fromJson(dto.toJson());

    expect(back.version, '0a1b2c3d');
    expect(back.clubsEnabled, isTrue);
    expect(back.crests, dto.crests);
    expect(CrestManifestDto.fromJson(const {}).crests, isEmpty);
    expect(CrestManifestDto.fromJson(const {}).clubsEnabled, isFalse);
  });

  test("the owner's page round-trips", () {
    const AdminCrestsDto dto = AdminCrestsDto(
      clubsEnabled: false,
      crests: <AdminCrestDto>[
        AdminCrestDto(slug: 'arsenal', status: 'active', url: 'https://x/a'),
        AdminCrestDto(
          slug: 'milan',
          status: 'deleted',
          reason: 'شكوى',
          complainant: 'club@x',
          changedAt: '2026-11-12T10:00:00.000Z',
        ),
      ],
      events: <CrestEventDto>[
        CrestEventDto(
          action: 'deleted',
          reason: 'شكوى',
          at: '2026-11-12T10:00:00.000Z',
          slug: 'milan',
          complainant: 'club@x',
        ),
      ],
    );

    final AdminCrestsDto back = AdminCrestsDto.fromJson(dto.toJson());

    expect(back.clubsEnabled, isFalse);
    expect(back.crests.last.url, isNull);
    expect(back.crests.last.complainant, 'club@x');
    expect(back.events.single.slug, 'milan');
    expect(back.toJson(), dto.toJson());
  });
}
