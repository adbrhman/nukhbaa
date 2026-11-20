import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

// NK290_19
/// Script 290: the admin's held announcements and the owners' review.
void main() {
  const Map<String, Object?> page = {
    'schema_version': 1,
    'requests': [
      {
        'id': '00000000-0220-4000-8220-0000000000a1',
        'author_name': 'سليمان',
        'title': 'تنبيه',
        'body': 'نص',
        'status': 'pending',
        'created_at': '2026-11-20T09:00:00.000Z',
        'decided_at': null,
        'recipients': null,
      },
    ],
  };

  test('myAnnouncements and ownerAnnouncements read their pages', () async {
    final ctx = buildTransport((request) async => okJson(page));
    final AdminApi api = AdminApi(ctx.transport);

    final mine = await api.myAnnouncements();
    final review = await api.ownerAnnouncements();

    expect(
      (mine as Ok<AnnouncementRequestsDto>).value.requests.single.status,
      'pending',
    );
    expect(review, isA<Ok<AnnouncementRequestsDto>>());
    expect(ctx.captured.map((r) => r.url.path), [
      '/admin/announcements/mine',
      '/owner/announcements',
    ]);
  });

  test('decideAnnouncement posts the action', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{'status': 'published'}),
    );

    final result = await AdminApi(
      ctx.transport,
    ).decideAnnouncement('00000000-0220-4000-8220-0000000000a1', publish: true);

    expect(result, const Result<String>.ok('published'));
    final sent = ctx.captured.single;
    expect(sent.method, 'POST');
    expect(
      sent.url.path,
      '/owner/announcements/00000000-0220-4000-8220-0000000000a1',
    );
    expect(jsonDecode(sent.body), {'action': 'publish'});
  });
}
