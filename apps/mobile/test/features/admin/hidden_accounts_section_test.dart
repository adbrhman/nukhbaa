/// The owner admin's hidden accounts (script 259) through the real
/// providers and the real `AdminApi`, over the auth harness's fake server:
/// the users section shows the tab to the owner admin alone; the tab lists
/// the hidden accounts, shows one again, and hides an account found by
/// name. Also drawn at 360px with text x2.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_shell.dart';
import 'package:mobile/features/admin/screens/sections/hidden_accounts_section.dart';
import 'package:mobile/features/auth/session_state.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _reviewer = '11111111-1111-4111-8111-111111111111';
const String _player = '22222222-2222-4222-8222-222222222222';

const AuthenticatedUserDto _owner = AuthenticatedUserDto(
  userId: 'u-owner',
  role: 'admin',
  status: 'active',
  email: 'Adbrhmanm@gmail.com',
);

const AuthenticatedUserDto _otherAdmin = AuthenticatedUserDto(
  userId: 'u-admin',
  role: 'admin',
  status: 'active',
  email: 'suleiman@example.com',
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _user(String id, String name, String email) => {
  'schema_version': 1,
  'id': id,
  'email': email,
  'display_name': name,
  'status': 'active',
};

final class _Server {
  _Server({this.me = _owner});

  final AuthenticatedUserDto me;
  final List<http.Request> requests = <http.Request>[];
  final Set<String> hidden = <String>{_reviewer};

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/hidden-accounts') {
      return _json({
        'schema_version': 1,
        'accounts': [
          if (hidden.contains(_reviewer))
            {
              'user': _user(_reviewer, 'مراجع التطبيق', 'r@t.io'),
              'hidden_at': '2026-11-11T20:00:00.000Z',
            },
          if (hidden.contains(_player))
            {
              'user': _user(_player, 'خالد', 'k@t.io'),
              'hidden_at': '2026-11-11T21:00:00.000Z',
            },
        ],
      });
    }
    if (path == '/admin/users') {
      return _json({
        'schema_version': 1,
        'users': [
          _user(_player, 'خالد', 'k@t.io'),
          _user('u-owner-id', 'عبدالرحمن', 'adbrhmanm@gmail.com'),
        ],
      });
    }
    if (path.startsWith('/admin/hidden-accounts/')) {
      final String id = path.split('/').last;
      final bool hide = request.method == 'POST';
      if (hide) {
        hidden.add(id);
      } else {
        hidden.remove(id);
      }
      return _json({'hidden': hide});
    }
    return okMe(me);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server,
  Widget body, {
  Size size = const Size(1080, 2340),
  double ratio = 3.0,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size / ratio,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: body),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  test('only the owner admin is the owner', () {
    expect(isOwnerAdminSession(const SessionAuthenticated(_owner)), isTrue);
    expect(
      isOwnerAdminSession(const SessionAuthenticated(_otherAdmin)),
      isFalse,
    );
    expect(
      isOwnerAdminSession(
        const SessionAuthenticated(
          AuthenticatedUserDto(
            userId: 'u-x',
            role: 'user',
            status: 'active',
            email: 'adbrhmanm@gmail.com',
          ),
        ),
      ),
      isFalse,
    );
    expect(isOwnerAdminSession(null), isFalse);
    expect(isOwnerAdminSession(const SessionUnauthenticated()), isFalse);
  });

  testWidgets('the owner admin sees the hidden accounts tab', (tester) async {
    await _open(tester, _Server(), const AdminUsersSection());

    expect(find.text('المخفيون'), findsOneWidget);
    expect(find.text('الجدد'), findsOneWidget);
  });

  testWidgets('another admin does not', (tester) async {
    await _open(tester, _Server(me: _otherAdmin), const AdminUsersSection());

    expect(find.text('الجدد'), findsOneWidget);
    expect(find.text('المخفيون'), findsNothing);
  });

  testWidgets('lists the hidden accounts and shows one again', (tester) async {
    final server = _Server();
    await _open(tester, server, const HiddenAccountsSection());

    expect(find.text('حسابات مخفية: 1'), findsOneWidget);
    expect(find.text('مراجع التطبيق'), findsOneWidget);
    await _tapVisible(tester, const Key('admin.hidden.show.$_reviewer'));

    final sent = server.to('/admin/hidden-accounts/$_reviewer').single;
    expect(sent.method, 'DELETE');
    expect(find.text('ظهر «مراجع التطبيق» ونقاطه في اللوحات'), findsOneWidget);
    expect(find.text('لا يوجد حساب مخفي'), findsOneWidget);
  });

  testWidgets('hides an account found by name, never the owner', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server, const HiddenAccountsSection());

    await tester.enterText(
      find.byKey(const Key('admin.hidden.searchField')),
      'خالد',
    );
    await _tapVisible(tester, const Key('admin.hidden.search'));

    expect(
      server.to('/admin/users').single.url.queryParameters['search'],
      'خالد',
    );
    expect(
      find.byKey(const Key('admin.hidden.found.$_player')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.hidden.found.u-owner-id')),
      findsNothing,
    );
    await _tapVisible(tester, const Key('admin.hidden.hide.$_player'));

    final sent = server.to('/admin/hidden-accounts/$_player').single;
    expect(sent.method, 'POST');
    expect(find.text('أُخفي «خالد» من كل اللوحات'), findsOneWidget);
    expect(find.text('حسابات مخفية: 2'), findsOneWidget);
  });

  testWidgets('an empty search asks for a name first', (tester) async {
    final server = _Server();
    await _open(tester, server, const HiddenAccountsSection());

    await _tapVisible(tester, const Key('admin.hidden.search'));

    expect(find.text('اكتب اسماً أو بريداً أولاً'), findsOneWidget);
    expect(server.to('/admin/users'), isEmpty);
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    await _open(
      tester,
      _Server(),
      const HiddenAccountsSection(),
      size: const Size(1080, 2340),
      ratio: 3.0,
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('مراجع التطبيق'), findsOneWidget);
  });
}
