/// The admin's Elite Cup panel through the real section, its real provider
/// and the real `AdminApi` / `LeaderboardsApi`, over the auth harness's fake
/// server: the champions are listed by month and path, a picture is added,
/// replaced and removed with the values the server needs -- and the panel
/// sits beside the month champion's panel in the hub.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_sections.dart';
import 'package:mobile/features/admin/admin_shell.dart';
import 'package:mobile/features/admin/screens/sections/champion_admin_section.dart';
import 'package:mobile/features/admin/screens/sections/cup_champions_admin_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

/// A 1x1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  _Server({this.empty = false});

  final bool empty;
  final List<http.Request> requests = <http.Request>[];
  bool hasPhoto = false;

  Map<String, Object?> _first() => <String, Object?>{
    'month_start': '2026-11-01',
    'place': 1,
    'how': 'final',
    'user_id': 'u-1',
    'display_name': 'Ahmad',
    if (hasPhoto) 'photo_url': '/cup-champions/2026-11-01/1/photo?v=1',
  };

  Map<String, Object?> _second() => <String, Object?>{
    'month_start': '2026-11-01',
    'place': 2,
    'how': 'walkover',
    'user_id': 'u-2',
    'display_name': 'Sara',
  };

  Map<String, Object?> _list() => <String, Object?>{
    'schema_version': 1,
    'champions': empty ? <Object?>[] : <Object?>[_first(), _second()],
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/cup-champions' && request.method == 'GET') {
      return _json(_list());
    }
    if (path == '/cup-champions/2026-11-01/1/photo') {
      return http.Response.bytes(
        _png,
        200,
        headers: const {'content-type': 'image/png'},
      );
    }
    if (path == '/admin/cup-champions/2026-11-01/1/photo') {
      hasPhoto = request.method == 'POST';
      return _json(_list());
    }
    if (path == '/months' || path == '/me/active-seasons') {
      return _json(<Object?>[]);
    }
    if (path == '/champions') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'champions': <Object?>[],
      });
    }
    return http.Response('not found', 404);
  }
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  ChampionPhotoPicker? pick,
  Widget? home,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body:
              home ??
              CupChampionsAdminSection(
                pickPhoto: pick ?? () async => (bytes: _png, mime: 'image/png'),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the champions are listed by month and path', (tester) async {
    await _open(tester, _Server());

    expect(find.text('نوفمبر 2026'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.cup.champion.2026-11-01.1')),
      findsOneWidget,
    );
    expect(find.text('Ahmad'), findsOneWidget);
    expect(find.textContaining('كأس النخبة ·'), findsOneWidget);
    expect(find.textContaining('كأس المسار الثاني'), findsOneWidget);
    expect(find.textContaining('تأهل بلا خصم'), findsOneWidget);
    // No prize anywhere on the panel.
    expect(find.textContaining('جائزة'), findsNothing);
    // Without a picture there is nothing to remove.
    expect(
      find.byKey(const Key('admin.cup.removePhoto.2026-11-01.1')),
      findsNothing,
    );
  });

  testWidgets('a month with no champion yet says so', (tester) async {
    await _open(tester, _Server(empty: true));
    expect(find.byKey(const Key('admin.cup.empty')), findsOneWidget);
  });

  testWidgets('a picture is added, then removed, with the right calls', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.cup.setPhoto.2026-11-01.1')));
    await tester.pumpAndSettle();

    final http.Request upload = server.requests.firstWhere(
      (r) =>
          r.method == 'POST' &&
          r.url.path == '/admin/cup-champions/2026-11-01/1/photo',
    );
    expect(upload.headers['content-type'], startsWith('image/png'));
    expect(upload.bodyBytes, _png);
    expect(
      find.byKey(const Key('admin.cup.removePhoto.2026-11-01.1')),
      findsOneWidget,
    );
    expect(find.text('تغيير الصورة'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('admin.cup.removePhoto.2026-11-01.1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();

    expect(
      server.requests.where(
        (r) =>
            r.method == 'DELETE' &&
            r.url.path == '/admin/cup-champions/2026-11-01/1/photo',
      ),
      hasLength(1),
    );
    expect(
      find.byKey(const Key('admin.cup.removePhoto.2026-11-01.1')),
      findsNothing,
    );
  });

  testWidgets('a picture over 512 KB is refused before anything is sent', (
    tester,
  ) async {
    final server = _Server();
    await _open(
      tester,
      server,
      pick: () async =>
          (bytes: Uint8List(championPhotoMaxBytes + 1), mime: 'image/png'),
    );

    await tester.tap(find.byKey(const Key('admin.cup.setPhoto.2026-11-01.2')));
    await tester.pumpAndSettle();

    expect(find.textContaining('512'), findsOneWidget);
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('the hub carries the cup panel beside the month champion', (
    tester,
  ) async {
    final server = _Server();
    await _open(
      tester,
      server,
      home: AdminShell(selected: AdminSection.champions, onSelect: (_) {}),
    );

    expect(find.byKey(const Key('admin.champions.tabs')), findsOneWidget);
    expect(find.byKey(const Key('admin.champions.list')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.champions.tab.1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.cup.list')), findsOneWidget);
    expect(find.text('Ahmad'), findsOneWidget);
  });
}
