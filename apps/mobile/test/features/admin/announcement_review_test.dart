/// Script 290: an admin's announcement held for review, through the real
/// `AdminApi` over faked sockets. The admin reads that it will be
/// published after its content is reviewed, and «لم يُعتمد للنشر» for one
/// rejected; never who reviews it. The owner's tab publishes or rejects.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/announcement_section.dart';
import 'package:mobile/features/admin/screens/sections/owner_announcements_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart'
    show AdminHarness, buildAdminHarness, okJsonObject;
import '../../support/auth_harness.dart' show buildAuthHarness, okMe;

const String _id = '00000000-0220-4000-8220-0000000000a1';

Map<String, Object?> _line(String status, {int? recipients}) => {
  'id': _id,
  'author_name': 'سليمان',
  'title': 'تنبيه الجمعة',
  'body': 'مباريات الجمعة تبدأ مبكرًا',
  'status': status,
  'created_at': '2026-11-20T09:00:00.000Z',
  'decided_at': status == 'pending' ? null : '2026-11-20T10:00:00.000Z',
  'recipients': recipients,
};

Widget _app(List<Override> overrides, Widget body) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    locale: const Locale('ar'),
    home: Scaffold(body: body),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
  ),
);

// NK290_20
void main() {
  testWidgets('an admin reads it pending, and a rejected one', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final AdminHarness harness = buildAdminHarness((request) async {
      if (request.url.path == '/admin/announcements/mine') {
        return okJsonObject({
          'schema_version': 1,
          'requests': [_line('rejected')],
        });
      }
      if (request.url.path == '/admin/announcements') {
        return okJsonObject({
          'schema_version': 1,
          'recipients': 0,
          'status': 'pending',
        });
      }
      return okJsonObject(const {});
    });
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      _app(harness.overrides, const AnnouncementSection()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('تنبيه الجمعة · لم يُعتمد للنشر'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('admin.announcement.titleField')),
      'تنبيه',
    );
    await tester.enterText(
      find.byKey(const Key('admin.announcement.bodyField')),
      'نص',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.announcement.sendButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.announcement.confirmSend')));
    await tester.pumpAndSettle();

    expect(
      find.text('تم إرسال الإشعار، وسيُنشر في كل التطبيق بعد مراجعة محتواه.'),
      findsOneWidget,
    );
    expect(find.textContaining('المالك'), findsNothing);
  });

  testWidgets('the owner publishes a held announcement', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    String status = 'pending';
    final List<http.Request> decided = <http.Request>[];
    final harness = buildAuthHarness((request) async {
      final String path = request.url.path;
      if (path == '/owner/announcements') {
        return http.Response(
          jsonEncode({
            'schema_version': 1,
            'requests': [
              _line(status, recipients: status == 'pending' ? null : 40),
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (path == '/owner/announcements/$_id') {
        decided.add(request);
        status = 'published';
        return http.Response(
          jsonEncode({'status': 'published', 'recipients': 40}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return okMe(
        const AuthenticatedUserDto(
          userId: 'u-owner-id',
          role: 'admin',
          status: 'active',
          isOwner: true,
        ),
      );
    }, seedToken: 'admin-jwt');
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      _app(harness.overrides, const OwnerAnnouncementsSection()),
    );
    await tester.pumpAndSettle();

    expect(find.text('مباريات الجمعة تبدأ مبكرًا'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('admin.ownerAnnouncements.publish.$_id')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.ownerAnnouncements.confirm')));
    await tester.pumpAndSettle();

    expect(jsonDecode(decided.single.body), {'action': 'publish'});
    expect(decided.single.method, 'POST');
    expect(find.textContaining('نُشر لـ40 لاعب'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.ownerAnnouncements.publish.$_id')),
      findsNothing,
    );
  });
}
