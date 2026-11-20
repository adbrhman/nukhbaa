/// Script 294: «المشرفون» on the owners' page, through the real providers
/// and `AdminApi` over the auth harness's fake server: an owner seat has no
/// revoke button; another admin is revoked only with a reason; a player
/// found by name is promoted.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/screens/sections/owner_admins_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart' show buildAuthHarness, okMe;

const String _owner = '11111111-1111-4111-8111-111111111111';
const String _admin = '22222222-2222-4222-8222-222222222222';
const String _player = '33333333-3333-4333-8333-333333333333';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

// NK294_16
final class _Server {
  final Set<String> admins = {_owner, _admin};
  final List<http.Request> acts = <http.Request>[];

  Map<String, Object?> _line(String id) => {
    'id': id,
    'display_name': id == _owner
        ? 'المالك'
        : (id == _admin ? 'سليمان' : 'خالد'),
    'email': null,
    'active': true,
    'is_owner': id == _owner,
  };

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == '/owner/admins') {
      return _json({
        'schema_version': 1,
        'admins': [for (final id in admins) _line(id)],
        'changes': <Object?>[],
      });
    }
    if (path.startsWith('/owner/admins/')) {
      acts.add(request);
      final String id = path.split('/').last;
      final String action =
          (jsonDecode(request.body) as Map<Object?, Object?>)['action']!
              as String;
      if (action == 'revoke') admins.remove(id);
      if (action == 'promote') admins.add(id);
      return _json({'action': action, 'sessions_ended': 1});
    }
    if (path == '/admin/users') {
      if (request.url.queryParameters['search'] == 'لا أحد') {
        return _json({'schema_version': 1, 'users': <Object?>[]});
      }
      return _json({
        'schema_version': 1,
        'users': [
          {
            'schema_version': 1,
            'id': _player,
            'email': 'k@t.io',
            'display_name': 'خالد',
            'status': 'active',
          },
        ],
      });
    }
    return okMe(
      const AuthenticatedUserDto(
        userId: _owner,
        role: 'admin',
        status: 'active',
        isOwner: true,
      ),
    );
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        // NK296_02
        // script 296: the real theme, whose buttons fill the width.
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        home: const Scaffold(body: OwnerAdminsSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an owner seat has no revoke; an admin is revoked', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    expect(find.byKey(const Key('admin.admins.revoke.$_owner')), findsNothing);
    await _tap(tester, const Key('admin.admins.revoke.$_admin'));
    expect(find.byKey(const Key('admin.admins.dialog.ok')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin.admins.dialog.reason')),
      'سوء استخدام',
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.admins.dialog.ok'));

    expect(jsonDecode(server.acts.single.body), {
      'action': 'revoke',
      'reason': 'سوء استخدام',
    });
    expect(find.byKey(const Key('admin.admins.row.$_owner')), findsOneWidget);
    expect(find.byKey(const Key('admin.admins.row.$_admin')), findsNothing);
  });

  testWidgets('a player found by name is promoted', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.enterText(
      find.byKey(const Key('admin.admins.searchField')),
      'خالد',
    );
    await _tap(tester, const Key('admin.admins.search'));
    await _tap(tester, const Key('admin.admins.promote.$_player'));
    await tester.enterText(
      find.byKey(const Key('admin.admins.dialog.reason')),
      'مشرف نتائج',
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.admins.dialog.ok'));

    expect(server.acts.single.url.path, '/owner/admins/$_player');
    expect(server.admins, contains(_player));
    // Once an admin, the search no longer offers him.
    expect(find.byKey(const Key('admin.admins.search')), findsOneWidget);
    expect(
      find.byKey(const Key('admin.admins.promote.$_player')),
      findsNothing,
    );
  });

  testWidgets('a search with no player says so', (tester) async {
    await _open(tester, _Server());

    await tester.enterText(
      find.byKey(const Key('admin.admins.searchField')),
      'لا أحد',
    );
    await _tap(tester, const Key('admin.admins.search'));

    expect(find.byKey(const Key('admin.admins.none')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
