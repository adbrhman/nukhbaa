import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

// NK346_02
/// Script 346: the owners' own audit log, read from `GET /owner/audit`.
void main() {
  // The two tables count their ids apart: id 5 is in both.
  final dto = OwnerAuditLogDto(
    entries: [
      OwnerAuditEntryDto(
        source: 'owner',
        id: 5,
        actorName: 'Owner One',
        method: 'PUT',
        path: '/owner/mode',
        at: DateTime.utc(2026, 11, 26, 20),
      ),
      OwnerAuditEntryDto(
        source: 'admin',
        id: 5,
        actorName: 'Owner One',
        method: 'PUT',
        path: '/fixtures/abc/result',
        at: DateTime.utc(2026, 11, 26, 19),
        target: 'Team A x Team B',
        result: '2-1',
      ),
    ],
  );

  test('ownerAudit reads the lines of both sources', () async {
    final ctx = buildTransport((request) async => okJson(dto.toJson()));

    final result = await AdminApi(ctx.transport).ownerAudit();

    final log = (result as Ok<OwnerAuditLogDto>).value;
    expect(log, dto);
    expect(log.entries.map((line) => line.source), ['owner', 'admin']);
    final sent = ctx.captured.single;
    expect(sent.method, 'GET');
    expect(sent.url.path, '/owner/audit');
  });

  test(
    'an account with no owner seat gets an error, not an empty log',
    () async {
      final ctx = buildTransport(
        (request) async =>
            errorEnvelope(404, 'route.not_found', 'Route not found'),
      );

      final result = await AdminApi(ctx.transport).ownerAudit();

      final error = (result as Err<OwnerAuditLogDto>).error;
      expect(error.kind, ErrorKind.invariant);
    },
  );

  test('a log that is not wired comes back as a transient error', () async {
    final ctx = buildTransport(
      (request) async => errorEnvelope(
        503,
        'owner.audit_unavailable',
        'The owner log is unavailable',
      ),
    );

    final result = await AdminApi(ctx.transport).ownerAudit();

    final error = (result as Err<OwnerAuditLogDto>).error;
    expect(error.code, 'owner.audit_unavailable');
    expect(error.kind, ErrorKind.transient);
  });

  test('a body without entries is an error, not an empty log', () async {
    final ctx = buildTransport(
      (request) async => okJson(const <String, Object?>{'schema_version': 1}),
    );

    final result = await AdminApi(ctx.transport).ownerAudit();

    expect(result, isA<Err<OwnerAuditLogDto>>());
  });
}
