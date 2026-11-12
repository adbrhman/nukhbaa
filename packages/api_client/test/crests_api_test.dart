import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// Scripts 265-266: the crests the app may show, their files, and the
/// owner's hands on them.
void main() {
  test('crestManifest reads the list', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{
        'schema_version': 1,
        'version': '0a1b2c3d',
        'clubs_enabled': true,
        'crests': {'arsenal': 'https://x/clubs/arsenal.1.png'},
      }),
    );

    final result = await TeamsApi(ctx.transport).crestManifest();

    final CrestManifestDto manifest = (result as Ok<CrestManifestDto>).value;
    expect(manifest.crests['arsenal'], 'https://x/clubs/arsenal.1.png');
    expect(ctx.captured.single.url.path, '/crests');
  });

  test('crestFile reads the public file without the credential', () async {
    final ctx = buildTransport(
      (request) async => http.Response.bytes(<int>[137, 80, 78, 71], 200),
    );

    final result = await TeamsApi(
      ctx.transport,
    ).crestFile('https://ref.supabase.co/storage/v1/object/public/c/a.png');

    expect((result as Ok<List<int>>).value, <int>[137, 80, 78, 71]);
    final sent = ctx.captured.single;
    expect(sent.url.host, 'ref.supabase.co');
    expect(sent.headers.containsKey('authorization'), isFalse);
  });

  test(
    'crestFile refuses a plain http URL and reports a missing file',
    () async {
      final ctx = buildTransport((request) async => http.Response('', 404));
      final TeamsApi api = TeamsApi(ctx.transport);

      final plain = await api.crestFile('http://ref.supabase.co/a.png');
      final missing = await api.crestFile('https://ref.supabase.co/a.png');

      expect((plain as Err<List<int>>).error.code, 'file.url_invalid');
      expect((missing as Err<List<int>>).error.code, 'file.unavailable');
      expect(ctx.captured, hasLength(1));
    },
  );

  test('actOnCrest posts the action, sending only what is set', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{'status': 'hidden'}),
    );

    final result = await AdminApi(
      ctx.transport,
    ).actOnCrest('arsenal', 'hide', reason: 'شكوى');

    expect(result, const Result<String>.ok('hidden'));
    final sent = ctx.captured.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/admin/crests/arsenal');
    expect(jsonDecode(sent.body), <String, Object?>{
      'action': 'hide',
      'reason': 'شكوى',
    });
  });

  test('setClubCrestsEnabled puts the switch and its reason', () async {
    final ctx = buildTransport(
      (request) async =>
          okJson(const <String, Object?>{'clubs_enabled': false}),
    );

    final result = await AdminApi(
      ctx.transport,
    ).setClubCrestsEnabled(false, reason: 'مراجعة');

    expect(result, const Result<bool>.ok(false));
    expect(ctx.captured.single.method, 'PUT');
    expect(jsonDecode(ctx.captured.single.body), <String, Object?>{
      'clubs_enabled': false,
      'reason': 'مراجعة',
    });
  });

  test('adminCrests reads the page', () async {
    const AdminCrestsDto dto = AdminCrestsDto(
      clubsEnabled: true,
      crests: <AdminCrestDto>[AdminCrestDto(slug: 'arsenal', status: 'active')],
      events: <CrestEventDto>[],
    );
    final ctx = buildTransport((request) async => okJson(dto.toJson()));

    final result = await AdminApi(ctx.transport).adminCrests();

    expect((result as Ok<AdminCrestsDto>).value.crests.single.slug, 'arsenal');
    expect(ctx.captured.single.url.path, '/admin/crests');
  });
}
