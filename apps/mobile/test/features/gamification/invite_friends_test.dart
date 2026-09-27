/// The invitation page through its real provider and the real `AuthApi`,
/// over the auth harness's fake server: the fixed code and the counters are
/// drawn, the link copied is the web link that carries the code, and a
/// claim sends the code with the install id and shows the server's answer.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/install_id.dart';
import 'package:mobile/features/gamification/invite_friends_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// Answers the two invitation routes and records what reached them.
final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/me/referral') {
      return _json(const {
        'schema_version': 1,
        'code': 'ABCDEFGH',
        'month_points': 3,
        'season_points': 7,
        'invited_count': 5,
        'pending_count': 2,
        'month_cap': 20,
      });
    }
    if (request.url.path == '/me/referral/claim') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return _json({
        'schema_version': 1,
        'status': body['code'] == 'ABCDEFGH' ? 'self_referral' : 'unknown_code',
      });
    }
    return okMe(sampleUser);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'saved-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        installIdStoreProvider.overrideWithValue(
          const FixedInstallIdStore('inst-12345678'),
        ),
      ],
      child: MaterialApp(
        home: const InviteFriendsScreen(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draws the fixed code and the counters', (tester) async {
    final server = _Server();
    await _open(tester, server);

    expect(find.text('ABCDEFGH'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('invite.monthPoints')),
        matching: find.text('3 من 20'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('invite.seasonPoints')),
        matching: find.text('7'),
      ),
      findsOneWidget,
    );
    final read = server.requests.firstWhere(
      (r) => r.url.path == '/me/referral',
    );
    expect(read.url.queryParameters['install'], 'inst-12345678');
  });

  testWidgets('the copied link is the web link that carries the code', (
    tester,
  ) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _open(tester, _Server());

    await tester.tap(find.byKey(const Key('invite.copyLink')));
    await tester.pumpAndSettle();

    final MethodCall copy = calls.lastWhere(
      (c) => c.method == 'Clipboard.setData',
    );
    final Map<Object?, Object?> args = copy.arguments as Map<Object?, Object?>;
    expect(args['text'], 'https://adbrhman.github.io/nukhbaa/?ref=ABCDEFGH');
  });

  testWidgets('a claim sends the code with the install id and shows the '
      'answer', (tester) async {
    final server = _Server();
    await _open(tester, server);

    // The list builds lazily: the claim card is below the fold and does
    // not exist until the page is scrolled to it.
    await tester.scrollUntilVisible(
      find.byKey(const Key('invite.claimButton')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite.claimField')),
      'zzzzzzzz',
    );
    await tester.ensureVisible(find.byKey(const Key('invite.claimButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invite.claimButton')));
    await tester.pumpAndSettle();

    final claim = server.requests.lastWhere(
      (r) => r.url.path == '/me/referral/claim',
    );
    final body = jsonDecode(claim.body) as Map<String, Object?>;
    expect(body['code'], 'zzzzzzzz');
    expect(body['install_id'], 'inst-12345678');
    expect(find.text(referralClaimMessage('unknown_code')), findsOneWidget);
  });

  test('the link carries the code; a late claim names the 24 hours', () {
    expect(inviteLinkFor('ABCDEFGH'), '$inviteWebBase?ref=ABCDEFGH');
    expect(referralClaimMessage('window_closed'), contains('24'));
  });
}
