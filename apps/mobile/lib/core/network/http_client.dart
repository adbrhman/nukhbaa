/// The ONE and ONLY place `apps/mobile` builds its `package:http` client (the
/// two small `platform_client_*.dart` files beside it pick the platform's).
///
/// `api_client`'s [ApiTransport] requires an injected `http.Client` (so it can
/// be driven by a `MockClient` in its own tests). This file constructs the
/// platform-default client and hands it to `api_client`; it makes NO request
/// itself. Every actual HTTP call is issued inside `api_client`, honouring the
/// "no HTTP in `apps/mobile`" rule (Flutter App phase constraint / ADR-002
/// §2.8) — this is dependency injection of a transport, not networking logic.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../auth/install_id.dart';
import 'platform_client_stub.dart'
    if (dart.library.io) 'platform_client_io.dart'
    as impl;

/// This install's id once the secure store answered (script 200). A
/// request never waits for the store: until it answers, requests go
/// without the header.
String? _installId;

String? _knownInstallId() => _installId;

/// Creates the platform-default [http.Client].
///
/// On native platforms this is the `dart:io`-backed client, with a bound on
/// how long a new connection may take (`platform_client_io.dart`); on web it
/// is the browser `fetch`-backed client. The caller owns the returned
/// client's lifecycle (it is closed when the owning provider is disposed).
///
/// Off the web it names this build on every request ([BuildHeaderClient],
/// script 142), so the server can refuse a release too old to be served,
/// and this install (script 200), so one phone never predicts a match
/// with two accounts and the admin sees the accounts that share it.
/// The web build sends no such header (a custom header would need a CORS
/// change): it reloads to the newest release by itself, and the server lets
/// a browser request through.
http.Client createHttpClient() {
  final http.Client client = impl.createPlatformClient();
  if (kIsWeb) {
    return client;
  }
  unawaited(
    appInstallIds.read().then((String? id) {
      _installId = id;
    }),
  );
  return BuildHeaderClient(
    client,
    build: const int.fromEnvironment('NUKHBA_BUILD_NUMBER'),
    installId: _knownInstallId,
  );
}
