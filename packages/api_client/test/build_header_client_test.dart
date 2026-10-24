import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Script 142: the app names its build on every request, through the real
/// [ApiTransport] over [BuildHeaderClient], and reads the server's refusal
/// of an old build as an invariant carrying the server's Arabic message
/// (the message `ErrorPresenter` shows as it is).
void main() {
  const String arabic = 'نسختك من نُخبة قديمة ولم تعد تعمل.';

  ({AppApi api, List<http.Request> seen}) build(
    Future<http.Response> Function(http.Request request) answer,
  ) {
    final List<http.Request> seen = <http.Request>[];
    final http.Client client = BuildHeaderClient(
      MockClient((http.Request request) async {
        seen.add(request);
        return answer(request);
      }),
      build: 775,
    );
    final ApiTransport transport = ApiTransport(
      baseUri: Uri.parse('https://api.test.example/'),
      httpClient: client,
      tokenProvider: () async => 'token',
      requestTimeout: null,
    );
    return (api: AppApi(transport), seen: seen);
  }

  test('every request carries the build number', () async {
    final app = build(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'code': 'app.build_unknown',
          'message': 'unknown',
        }),
        503,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );

    await app.api.latestBuild();
    await app.api.latestBuild();

    expect(app.seen, hasLength(2));
    for (final http.Request request in app.seen) {
      expect(request.headers[appBuildHeader], '775');
      expect(request.headers['authorization'], 'Bearer token');
    }
  });

  test('the server\'s refusal of an old build reaches the app as an '
      'invariant with its Arabic message', () async {
    final app = build(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schema_version': 1,
            'code': 'app.update_required',
            'message': arabic,
          }),
        ),
        409,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      ),
    );

    final Result<LatestBuildDto> read = await app.api.latestBuild();

    final AppError error = (read as Err<LatestBuildDto>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'app.update_required');
    expect(error.message, arabic);
  });
}
