/// The admin's invitation page through its real provider and the real
/// `AdminApi`, over the auth harness's fake server: it draws the switch,
/// the totals, each invitation's state and reason, and the inviters; the
/// switch and the decisions reach the server with their values.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/referral_admin_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/admin/referral-overview') {
      return _json(const {
        'schema_version': 1,
        'enabled': true,
        'state_counts': {'held': 1, 'revoked': 1},
        'referrers': [
          {
            'referrer_id': 'r-1',
            'referrer_name': 'Ali',
            'invited': 2,
            'paid': 0,
            'pending': 0,
            'held': 1,
            'refused': 1,
            'month_points': 0,
          },
        ],
        'invitations': [
          {
            'invitee_id': 'i-held',
            'invitee_name': 'Sami',
            'invitee_status': 'active',
            'referrer_id': 'r-1',
            'referrer_name': 'Ali',
            'claimed_at': '2026-10-05T06:05:00.000Z',
            'state': 'held',
            'hold_reasons': ['shared_network'],
          },
          {
            'invitee_id': 'i-idle',
            'invitee_name': 'Badr',
            'invitee_status': 'suspended',
            'referrer_id': 'r-1',
            'referrer_name': 'Ali',
            'claimed_at': '2026-10-01T07:05:00.000Z',
            'state': 'revoked',
            'hold_reasons': <String>[],
            'revoke_reason': 'inactive_7_days',
            'last_prediction_at': '2026-10-02T09:00:00.000Z',
          },
        ],
      });
    }
    if (request.url.path == '/admin/referral-switch') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return _json({'schema_version': 1, 'enabled': body['enabled']});
    }
    if (request.url.path.startsWith('/admin/referrals/')) {
      return _json(const {'schema_version': 1, 'status': 'approved'});
    }
    return okMe(sampleUser);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const Scaffold(body: ReferralAdminSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draws the switch, the totals and each invitation', (
    tester,
  ) async {
    await _open(tester, _Server());

    final SwitchListTile toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('admin.referrals.switch')),
    );
    expect(toggle.value, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.referrals.count.held')),
        matching: find.text('محجوزة للمراجعة: 1'),
      ),
      findsOneWidget,
    );
    await _scrollTo(
      tester,
      find.byKey(const Key('admin.referrals.invitation.i-idle')),
    );
    expect(find.text('سبب السحب: خمول 7 أيام بلا توقعات'), findsOneWidget);
    expect(find.text('الحساب موقوف'), findsOneWidget);
    await _scrollTo(
      tester,
      find.byKey(const Key('admin.referrals.referrer.r-1')),
    );
    expect(find.text('نقاط الدعوة هذا الشهر: 0 من 20'), findsOneWidget);
  });

  testWidgets('the switch sends off to the server', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.referrals.switch')));
    await tester.pumpAndSettle();

    final put = server.requests.lastWhere(
      (r) => r.url.path == '/admin/referral-switch',
    );
    expect(put.method, 'PUT');
    expect((jsonDecode(put.body) as Map<String, Object?>)['enabled'], false);
    expect(find.text('تم إيقاف نظام الدعوات'), findsOneWidget);
  });

  testWidgets('approving a held invitation sends the reason', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _scrollTo(
      tester,
      find.byKey(const Key('admin.referrals.approve.i-held')),
    );
    await tester.tap(find.byKey(const Key('admin.referrals.approve.i-held')));
    await tester.pumpAndSettle();

    // A reason shorter than three letters is refused in the dialog.
    await tester.enterText(
      find.byKey(const Key('admin.referrals.reasonField')),
      'ok',
    );
    await tester.tap(find.byKey(const Key('admin.referrals.reasonConfirm')));
    await tester.pumpAndSettle();
    expect(
      server.requests.where((r) => r.url.path.startsWith('/admin/referrals/')),
      isEmpty,
    );

    await tester.enterText(
      find.byKey(const Key('admin.referrals.reasonField')),
      'brothers, one house',
    );
    await tester.tap(find.byKey(const Key('admin.referrals.reasonConfirm')));
    await tester.pumpAndSettle();

    final post = server.requests.lastWhere(
      (r) => r.url.path == '/admin/referrals/i-held',
    );
    final body = jsonDecode(post.body) as Map<String, Object?>;
    expect(body['decision'], 'approve');
    expect(body['reason'], 'brothers, one house');
    expect(find.text('تم قبول الدعوة واحتسابها'), findsOneWidget);
  });
}
