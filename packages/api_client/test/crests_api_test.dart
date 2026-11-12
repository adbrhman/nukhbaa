import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

/// Script 265: the crests the app may show, and the owner's hands on them.
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
