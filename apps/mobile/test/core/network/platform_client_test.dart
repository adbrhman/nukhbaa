import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:mobile/core/network/platform_client_io.dart';

/// A connection that never completes (a mobile network dropping packets)
/// must not hold a request for the transport's whole 35 s timeout: the
/// native client gives up on connecting after [connectTimeout], so the
/// call fails as a network error and `ApiTransport` repeats a GET once.
void main() {
  test('the native client is an IOClient with a bounded connect', () {
    final client = createPlatformClient();
    addTearDown(client.close);

    expect(client, isA<IOClient>());
    expect(connectTimeout, const Duration(seconds: 10));
    expect(connectTimeout, lessThan(const Duration(seconds: 35)));
  });
}
