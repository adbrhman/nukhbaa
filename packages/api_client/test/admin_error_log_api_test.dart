import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  test('GET /admin/errors sends the list and the code', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'counts': {'all': 3, 'new': 2, 'recurring': 1, 'critical': 0},
        'errors': <Object?>[],
        'admins': <Object?>[],
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).errorLog(list: 'recurring', code: 'K7Q2');

    final page = (result as Ok<AdminErrorListDto>).value;
    expect(page.fresh, 2);
    expect(page.recurring, 1);
    final url = ctx.captured.single.url;
    expect(url.path, '/admin/errors');
    expect(url.queryParameters, {'list': 'recurring', 'code': 'K7Q2'});
  });

  test('POST /admin/errors/{id} sends only what changes', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {
        'schema_version': 1,
        'error': {'id': 7, 'problem_code': 'K7Q2', 'status': 'fixed'},
        'samples': <Object?>[],
        'builds': <Object?>[],
      }),
    );

    final result = await AdminApi(
      ctx.transport,
    ).updateError(7, const AdminErrorUpdateDto(status: 'fixed', notes: ''));

    expect((result as Ok<AdminErrorDetailDto>).value.error.status, 'fixed');
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/admin/errors/7');
    expect(jsonDecode(req.body), {'status': 'fixed', 'notes': ''});
  });
}
