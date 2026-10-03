import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

({ApiTransport transport, List<ApiFailure> failures}) _listening(
  Future<http.Response> Function(http.Request request) handler,
) {
  final failures = <ApiFailure>[];
  final transport = ApiTransport(
    baseUri: Uri.parse('https://api.test.example/'),
    httpClient: MockClient(handler),
    tokenProvider: () async => null,
    requestTimeout: null,
    onFailure: failures.add,
  );
  return (transport: transport, failures: failures);
}

void main() {
  test('POST /errors/report sends the report and reads the code', () async {
    final ctx = buildTransport(
      (_) async => okJson(const {'schema_version': 1, 'problem_code': 'K7Q2'}),
      token: null,
    );

    final result = await AppApi(ctx.transport).reportError(
      const ClientErrorReportDto(
        source: 'android',
        errorType: 'StateError',
        message: 'Bad state: boom',
        build: 'abc1234',
        fatal: true,
      ),
    );

    expect((result as Ok<ClientErrorReportAckDto>).value.problemCode, 'K7Q2');
    final req = ctx.captured.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/errors/report');
    expect(req.headers.containsKey('authorization'), isFalse);
    final body = jsonDecode(req.body) as Map<String, Object?>;
    expect(body['source'], 'android');
    expect(body['fatal'], isTrue);
    expect(body.containsKey('stack'), isFalse);
  });

  test('a 5xx envelope hands its problem code to the caller', () async {
    final ctx = buildTransport(
      (_) async => http.Response(
        jsonEncode({
          'schema_version': 1,
          'code': 'db.timeout',
          'message': 'timed out',
          'problem_code': 'S7L9',
        }),
        503,
      ),
    );

    final result = await AppApi(ctx.transport).latestBuild();

    final error = (result as Err<LatestBuildDto>).error;
    expect(error.code, 'db.timeout');
    expect(error.problemCode, 'S7L9');
  });

  test('every failed call reaches the listener with its request id', () async {
    final ctx = _listening(
      (_) async => http.Response(
        '',
        502,
        headers: const {'x-request-id': '0123456789abcdef'},
      ),
    );

    await AppApi(ctx.transport).latestBuild();

    final failure = ctx.failures.single;
    expect(failure.method, 'GET');
    expect(failure.path, '/app/latest-build');
    expect(failure.statusCode, 502);
    expect(failure.requestId, '0123456789abcdef');
    expect(failure.error.code, apiErrorUnexpectedStatus);
  });

  test('a success reaches no listener; a broken body does', () async {
    final ok = _listening(
      (_) async => okJson(const {
        'schema_version': 2,
        'published_at': '2026-10-03T00:00:00Z',
        'apk_url': 'https://example.com/app.apk',
      }),
    );
    await AppApi(ok.transport).latestBuild();
    expect(ok.failures, isEmpty);

    final broken = _listening((_) async => http.Response('not json', 200));
    await AppApi(broken.transport).latestBuild();
    expect(broken.failures.single.error.code, apiErrorMalformedResponse);
  });

  test('a listener that throws never breaks the call', () async {
    final transport = ApiTransport(
      baseUri: Uri.parse('https://api.test.example/'),
      httpClient: MockClient((_) async => http.Response('', 500)),
      tokenProvider: () async => null,
      requestTimeout: null,
      onFailure: (_) => throw StateError('listener'),
    );

    final result = await AppApi(transport).latestBuild();

    expect(result.isErr, isTrue);
  });
}
