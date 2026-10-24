import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/network/http_client.dart';

/// Script 142: the app's one HTTP client, which both transports use (the
/// session's and the error reporter's), names the build on every request
/// off the web; `build_header_client_test.dart` (api_client) proves the
/// header reaches the server through the real transport.
void main() {
  test('the app\'s http client names the build on Android and iOS', () {
    final http.Client client = createHttpClient();
    addTearDown(client.close);

    expect(client, isA<BuildHeaderClient>());
  });
}
