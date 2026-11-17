/// The native (`dart:io`) HTTP client, with a bound on how long it waits to
/// connect. Chosen by `http_client.dart` through a conditional import; the
/// web build uses `platform_client_stub.dart` instead.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// How long a new connection may take to open before it is given up.
///
/// `dart:io`'s `HttpClient` has no limit of its own: a connection that never
/// completes (a mobile network that drops packets, a switch between Wi-Fi
/// and mobile data) waits for the transport's whole request timeout (35 s)
/// and surfaces as `api_client.timeout` ("The server took too long to
/// respond") although no server was ever reached. With this limit it fails
/// as a network error instead, and `ApiTransport` repeats a GET once on a
/// fresh connection.
const Duration connectTimeout = Duration(seconds: 10);

/// Creates the native client: `dart:io`'s, with [connectTimeout] applied.
/// The idle timeout is left at the platform default.
http.Client createPlatformClient() {
  final HttpClient inner = HttpClient()..connectionTimeout = connectTimeout;
  return IOClient(inner);
}
