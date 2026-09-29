/// The web build's update check through the real [UpdateGate], the real
/// `AppApi` and `GET /app/latest-build`, with only the socket faked
/// ([buildAuthHarness]): a page running an older build than the newest
/// release is offered a reload, the current build is left alone, a refusal
/// is not asked again straight away, and a local run without a build id
/// never asks at all.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/update/update_gate.dart';

import '../../support/auth_harness.dart';

final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/app/latest-build') {
      return http.Response(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'published_at': '2026-09-29T03:00:00Z',
          'apk_url':
              'https://github.com/adbrhman/nukhbaa/releases/download/'
              'build-bbbbbbb/app-arm64-v8a-release.apk',
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return http.Response('not found', 404);
  }

  int get checks =>
      requests.where((r) => r.url.path == '/app/latest-build').length;
}

/// The offer memory, in memory: platform storage never answers under
/// `flutter test`.
final class _Memory implements UpdateOfferMemory {
  _Memory([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

Future<List<int>> _open(
  WidgetTester tester,
  _Server server, {
  required String buildSha,
  _Memory? memory,
}) async {
  final List<int> reloads = <int>[];
  final harness = buildAuthHarness(server.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        pageReloaderProvider.overrideWithValue(() => reloads.add(1)),
        updateOfferMemoryProvider.overrideWithValue(memory ?? _Memory()),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        home: UpdateGate(
          isWeb: true,
          buildSha: buildSha,
          child: const Text('child-visible'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reloads;
}

void main() {
  testWidgets('an older page is offered a reload, and reloads', (tester) async {
    final server = _Server();
    final List<int> reloads = await _open(tester, server, buildSha: 'aaaaaaa');

    expect(server.checks, 1);
    expect(find.text('child-visible'), findsOneWidget);
    expect(find.byKey(const Key('update.web.reload')), findsOneWidget);

    await tester.tap(find.byKey(const Key('update.web.reload')));
    await tester.pumpAndSettle();

    expect(reloads, hasLength(1));
  });

  testWidgets('the current build is left alone', (tester) async {
    final server = _Server();
    final List<int> reloads = await _open(tester, server, buildSha: 'bbbbbbb');

    expect(server.checks, 1);
    expect(find.byKey(const Key('update.web.reload')), findsNothing);
    expect(reloads, isEmpty);
  });

  testWidgets('later: no reload, and no second ask on a quick return', (
    tester,
  ) async {
    final server = _Server();
    final List<int> reloads = await _open(tester, server, buildSha: 'aaaaaaa');

    await tester.tap(find.byKey(const Key('update.web.later')));
    await tester.pumpAndSettle();
    expect(reloads, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(server.checks, 1);
    expect(find.byKey(const Key('update.web.reload')), findsNothing);
  });

  testWidgets('a release offered minutes ago is not offered again', (
    tester,
  ) async {
    // The release goes up before the web build: a reload in that window
    // lands on the old build, which must not ask again at once.
    final server = _Server();
    final _Memory memory = _Memory(
      '2026-09-29T03:00:00Z@${DateTime.now().toUtc().toIso8601String()}',
    );
    final List<int> reloads = await _open(
      tester,
      server,
      buildSha: 'aaaaaaa',
      memory: memory,
    );

    expect(server.checks, 1);
    expect(find.byKey(const Key('update.web.reload')), findsNothing);
    expect(reloads, isEmpty);
  });

  testWidgets('the offer is remembered with its release', (tester) async {
    final server = _Server();
    final _Memory memory = _Memory();
    await _open(tester, server, buildSha: 'aaaaaaa', memory: memory);

    expect(memory.value, startsWith('2026-09-29T03:00:00Z@'));
  });

  testWidgets('a local run without a build id never asks', (tester) async {
    final server = _Server();
    final List<int> reloads = await _open(tester, server, buildSha: '');

    expect(server.checks, 0);
    expect(find.byKey(const Key('update.web.reload')), findsNothing);
    expect(reloads, isEmpty);
  });
}
