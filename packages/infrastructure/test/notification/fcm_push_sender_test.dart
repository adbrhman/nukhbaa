import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// A throwaway RSA key made for this test alone. It signs the service-account
/// assertion, which the mocked token endpoint never checks; it grants nothing.
const String _testKey = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCzgbEsu83rfkO/
SN9JHjVBGg4ANtHzpAlvI27kRn2tsixBECbIEV3GwHYYWNZdNnCC0lksbnUcPeX3
nLqYbYKKuUuztMUhklNPlaJvo5exBoGYLWZH08qSpQY3L8/PhPbeCFgChjBLChss
GSCfAqdSnRr/ZzdLaVec7VZoFkOg6GYNR/tMqNpien2eb8XfDbEUCH2tGOiMsFbA
2rmy95vDzPJvm319LdkH3ufFUWvJ4S4BgxtGXi4CTof5lvHg0hspkcSScCglv81r
Qq7hYlBFBqqNUNUJTuvReAFAEGRkcPzkrO5ZhSnII7F9T/p65kc0EUGYxOaauz7K
2xPea0ffAgMBAAECggEACCxXjNngPmC5ZPREdmfRtO0ixg+474cAhvbuDabIAiii
qzO5EFL6GhqZRfKFkCjyZoJ9XPCKlIac+fFA7b/OudJGCCCq+SRYdr8xbjPcrErH
i85FYe/awWKSLeEXbTN4qhNnLnY9rK0BH7jlK1hLlg9hM0/XzK83NgX4cTTST3kx
vjVlG49Q5PgWT0Y7owj1Ob1N/A+M2TTyP5QG/n6S9qFbb1hOUr1sRxdAQUHWmuzA
kQaa3MTUkKQBwzNGElBHAF85BXSRrumimza8IjSZcNMn+HHbXaV9/Mt12ByoS4tu
gj93/27Rlj7A53yPddPXbT+JerXRIjQ8WAQWs/bNAQKBgQDzhZPwRYg3/1yPshtc
rbomLkEjDxFvwdVOq2hZlyzhL8++VvSPx7ZobhDXZzMUXlglV/PqTsBoATj8UmH0
eg1ojtiHMFgXJzFc4GhoqHqJJVZvz7XsEW8kFk4IRx2yqPFif3v6Si/Isjm5weYU
BKs9uxExlKW4IXvw42ka/sSOzwKBgQC8tGN1U53ZnK8mQbscNxvtf0yGbNM7pPQh
FvelNhS6IbAoXlYkWozM3iKJzc9s+VEkTllS/oGFBScvESfXLJJ7pHwJgd8s1cdG
QqxYrCU8BTaua8aCD9JtoEXitBnHrXPCZrzFe9/uCNgyOIrvLeIMz5D8myyUDFjS
r9DLkk958QKBgQCaBucnlhMuuAnnqZO87vVKqP7yGdnBgixU8f2yjPgKBp+zmHRf
bMZnDxb/53pba8D8/cB9dwojvoI4tjLW20wX0iIKf/13x4ZlZFslt0qp7D/bwNkk
U3KktKbufWy/UDQ9RL059ip7Gp+AarAIAVv+U4/weEDJUgR+vJgCRxoz6QKBgHAG
Ps0WGK1pQOlbODMl3CR/3/Qlgrjz0iIaumWP13owKZ2tc0Idp1yvup1IWw18bNk6
0fhdMpK/XmWor5gj08om+aPDP7QkLSrexeXWPDyHc9DUFoJ71hZSgWp2NJ+/rusH
hqVORr/O7FnUC1a2TG4CgzYTAMHbGpfo2/EeKKRhAoGAY7Nq1c75HmoALuOJoGuW
5cKc664FpGrdmgzfgu8oJpjoXdzpp7HPQXIvflGWWRrrJZzkB6fHe/nfyQpOzTU6
tHYReeMMEBegRwgjKkqCTDcKeKTyDnZ8KYKgTO4w/q2oLDEQBl2+OgbB3coxId68
J77Gv87uKdHxia+Uf4zQwTY=
-----END PRIVATE KEY-----
''';

Map<String, Object?> _account() => <String, Object?>{
  'project_id': 'nukhbaa-test',
  'client_email': 'push@nukhbaa-test.iam.gserviceaccount.com',
  'private_key': _testKey,
};

bool _isTokenEndpoint(http.Request request) =>
    request.url.host == 'oauth2.googleapis.com';

http.Response _tokenResponse() => http.Response(
  jsonEncode(<String, Object?>{'access_token': 'token', 'expires_in': 3600}),
  200,
);

void main() {
  group('FcmPushSender request timeout', () {
    test('a message send that never answers is abandoned, not awaited '
        'forever', () async {
      var sends = 0;
      final sender = FcmPushSender(
        serviceAccount: _account(),
        httpClient: MockClient((request) {
          if (_isTokenEndpoint(request)) {
            return Future<http.Response>.value(_tokenResponse());
          }
          sends++;
          return Completer<http.Response>().future;
        }),
        requestTimeout: const Duration(milliseconds: 50),
      );

      final result = await sender
          .send(tokens: const <String>['a', 'b'], title: 't', body: 'b')
          .timeout(const Duration(seconds: 5));

      expect(result, isA<Ok<List<String>>>());
      // A silent token is a transient failure: it is never retired as dead.
      expect((result as Ok<List<String>>).value, isEmpty);
      // The first silent message did not stop the second from being tried.
      expect(sends, 2);
    });

    test('a token endpoint that never answers fails as transient', () async {
      final sender = FcmPushSender(
        serviceAccount: _account(),
        httpClient: MockClient((_) => Completer<http.Response>().future),
        requestTimeout: const Duration(milliseconds: 50),
      );

      final result = await sender
          .send(tokens: const <String>['a'], title: 't', body: 'b')
          .timeout(const Duration(seconds: 5));

      expect(result, isA<Err<List<String>>>());
      expect(
        (result as Err<List<String>>).error.code,
        'push.token_exchange_failed',
      );
    });

    test('answers within the timeout still report dead tokens', () async {
      final sender = FcmPushSender(
        serviceAccount: _account(),
        httpClient: MockClient((request) async {
          if (_isTokenEndpoint(request)) {
            return _tokenResponse();
          }
          final bool dead = request.body.contains('"token":"gone"');
          return http.Response(dead ? 'UNREGISTERED' : '{}', dead ? 404 : 200);
        }),
        requestTimeout: const Duration(seconds: 5),
      );

      final result = await sender.send(
        tokens: const <String>['live', 'gone'],
        title: 't',
        body: 'b',
      );

      expect((result as Ok<List<String>>).value, <String>['gone']);
    });
  });
}
