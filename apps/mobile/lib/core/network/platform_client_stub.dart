/// The HTTP client where `dart:io` is not there (the browser). Chosen by
/// `http_client.dart` through a conditional import; native builds use
/// `platform_client_io.dart` instead.
library;

import 'package:http/http.dart' as http;

/// Creates the browser's `fetch`-backed client. The browser owns connection
/// handling, so there is nothing to configure here.
http.Client createPlatformClient() => http.Client();
