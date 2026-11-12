/// The owner admin's people (script 264, over script 263's routes) through
/// the real provider and the real `AdminApi`, over the auth harness's fake
/// server: a linked person is listed with his accounts, a new one is set
/// from a search (main, second, hidden), one is changed and one unlinked.
/// Also drawn at 360px with text x2.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/person_links_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';
const String _c = '33333333-3333-4333-8333-333333333333';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _user(String id, String name) => {
  'schema_version': 1,
  'id': id,
  'email': '$id@t.io',
  'display_name': name,
  'status': 'active',
};

final class _Server {
  final List<http.Request> requests = <http.Request>[];
  bool linked = true;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/person-links') {
      return _json({
        'schema_version': 1,
        'people': [
          if (linked)
            {
              'main_id': _a,
              'accounts': [
                {
                  'user': _user(_a, 'عبدالرحمن المغربي'),
                  'counted': true,
                  'hidden': false,
                },
                {
                  'user': _user(_b, 'عبد الرحمن المغربي'),
                  'counted': false,
                  'hidden': true,
                },
              ],
            },
        ],
      });
    }
    if (path == '/admin/users') {
      return _json({
        'schema_version': 1,
        'users': [
          _user(_a, 'عبدالرحمن المغربي'),
          _user(_b, 'عبد الرحمن المغربي'),
          _user(_c, 'عبدالرحمن محمد المغربي'),
        ],
      });
    }
    if (path.startsWith('/admin/person-links/')) {
      if (request.method == 'DELETE') {
        linked = false;
        return _json({'unlinked': 2});
      }
      return _json({'set': true});
    }
    return okMe(sampleUser);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  double height = 9000,
  double textScale = 1.0,
}) async {
  final Size size = Size(1080, height);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
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
            size: size / 3.0,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: PersonLinksSection()),
        ),
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

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('admin.people.searchField')),
    'المغربي',
  );
  await _tap(tester, const Key('admin.people.search'));
}

void main() {
  testWidgets('lists a linked person, the main account first', (tester) async {
    await _open(tester, _Server());

    expect(find.text('أشخاص مربوطون: 1'), findsOneWidget);
    expect(find.text('عبدالرحمن المغربي · أساسي'), findsOneWidget);
    expect(find.text('عبد الرحمن المغربي · مخفي'), findsOneWidget);
  });

  testWidgets('sets a person from a search: main, second, hidden', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await _search(tester);
    await _tap(tester, const Key('admin.people.role.$_c.main'));
    await _tap(tester, const Key('admin.people.role.$_a.second'));
    await _tap(tester, const Key('admin.people.role.$_b.hidden'));
    await _tap(tester, const Key('admin.people.save'));

    final sent = server.to('/admin/person-links/$_c').single;
    expect(sent.method, 'PUT');
    expect(jsonDecode(sent.body), {
      'second_id': _a,
      'other_ids': [_b],
    });
    expect(find.text('رُبطت الحسابات، وأُخفي 1 من كل اللوحات'), findsOneWidget);
    expect(find.byKey(const Key('admin.people.save')), findsNothing);
  });

  testWidgets('a second main moves the first to the hidden ones', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await _search(tester);
    await _tap(tester, const Key('admin.people.role.$_a.main'));
    await _tap(tester, const Key('admin.people.role.$_c.main'));
    await _tap(tester, const Key('admin.people.save'));

    expect(jsonDecode(server.to('/admin/person-links/$_c').single.body), {
      'other_ids': [_a],
    });
  });

  testWidgets('without a main account nothing is sent', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _search(tester);
    await _tap(tester, const Key('admin.people.role.$_a.hidden'));
    await _tap(tester, const Key('admin.people.role.$_b.hidden'));
    await _tap(tester, const Key('admin.people.save'));

    expect(find.text('اختر الحساب الأساسي'), findsOneWidget);
    expect(
      server.requests.where(
        (r) => r.url.path.startsWith('/admin/person-links/'),
      ),
      isEmpty,
    );
  });

  testWidgets('a person is changed from its card', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _tap(tester, const Key('admin.people.edit.$_a'));
    await _tap(tester, const Key('admin.people.draftRole.$_b.second'));
    await _tap(tester, const Key('admin.people.save'));

    expect(jsonDecode(server.to('/admin/person-links/$_a').single.body), {
      'second_id': _b,
      'other_ids': <Object?>[],
    });
  });

  testWidgets('unlinking asks first', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _tap(tester, const Key('admin.people.unlink.$_a'));
    expect(find.text('فك ربط «عبدالرحمن المغربي»؟'), findsOneWidget);
    await tester.tap(find.text('فك الربط').last);
    await tester.pumpAndSettle();

    expect(server.to('/admin/person-links/$_a').single.method, 'DELETE');
    expect(find.text('لا يوجد شخص مربوط'), findsOneWidget);
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    await _open(tester, _Server(), height: 2340, textScale: 2.0);
    await _search(tester);
    await _tap(tester, const Key('admin.people.role.$_a.main'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('admin.people.found.$_a')), findsOneWidget);
  });
}
