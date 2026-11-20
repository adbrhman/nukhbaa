import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

// NK290_18
/// Script 290: the held announcements and the send's status survive the
/// wire unchanged.
void main() {
  test('a held announcement round-trips through JSON', () {
    final AnnouncementRequestsDto dto = AnnouncementRequestsDto(
      requests: [
        AnnouncementRequestDto(
          id: '00000000-0220-4000-8220-0000000000a1',
          authorName: 'سليمان',
          title: 'تنبيه',
          body: 'نص',
          status: 'published',
          createdAt: DateTime.utc(2026, 11, 20, 9),
          decidedAt: DateTime.utc(2026, 11, 20, 10),
          recipients: 12,
        ),
      ],
    );

    final Map<String, Object?> json = dto.toJson();

    expect(AnnouncementRequestsDto.fromJson(json), dto);
    final Map<String, Object?> line =
        (json['requests']! as List<Object?>).single! as Map<String, Object?>;
    expect(line['decided_at'], '2026-11-20T10:00:00.000Z');
  });

  test('a send answers its status; an old server means published', () {
    const AnnouncementPublishedDto pending = AnnouncementPublishedDto(
      recipients: 0,
      status: AnnouncementPublishedDto.pending,
    );

    expect(AnnouncementPublishedDto.fromJson(pending.toJson()), pending);
    expect(
      AnnouncementPublishedDto.fromJson(const {'recipients': 3}).status,
      AnnouncementPublishedDto.published,
    );
  });
}
