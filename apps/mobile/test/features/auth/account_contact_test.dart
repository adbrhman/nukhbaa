/// The account tab's way to the developer (2026-10-27), through the real
/// [AccountScreen] over the real [ApiTransport]: a support group after the
/// app's settings whose row opens a mail to Nukhbaa's support address
/// (script 164; no phone number anywhere) through the app's link opener,
/// and says so when nothing could open it.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/account_screen.dart';
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const AuthenticatedUserDto _player = AuthenticatedUserDto(
  userId: 'u-1',
  role: 'user',
  status: 'active',
  email: 'a@example.com',
  displayName: 'سامي',
);

Future<List<Uri>> _pump(
  WidgetTester tester, {
  bool opens = true,
  double textScale = 1,
  Size size = const Size(1080, 4000),
}) async {
  final List<Uri> opened = <Uri>[];
  final AuthHarness harness = buildAuthHarness(
    (http.Request request) async => http.Response('not found', 404),
    seedToken: 'jwt',
  );
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        notificationLinkOpenerProvider.overrideWithValue((Uri uri) async {
          opened.add(uri);
          return opens;
        }),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AccountScreen(user: _player),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

const Key _row = Key('account.contactDeveloper');

void main() {
  testWidgets('the support row opens a mail to the support address', (
    tester,
  ) async {
    final List<Uri> opened = await _pump(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('account.group.support')),
        matching: find.byKey(_row),
      ),
      findsOneWidget,
    );
    expect(find.text('الدعم'), findsOneWidget);
    expect(find.text('تواصل مع المطوّر'), findsOneWidget);
    // The player sees the support address on the row; no WhatsApp.
    expect(
      find.text(
        'للإبلاغ عن مشكلة أو تقديم شكوى عبر البريد\nnukhbaa.app@gmail.com',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('واتساب'), findsNothing);
    // After the app's settings, before sign-out.
    final double app = tester
        .getTopLeft(find.byKey(const Key('account.group.app')))
        .dy;
    final double support = tester
        .getTopLeft(find.byKey(const Key('account.group.support')))
        .dy;
    final double signOut = tester
        .getTopLeft(find.byKey(const Key('account.signOut')))
        .dy;
    expect(app, lessThan(support));
    expect(support, lessThan(signOut));

    await tester.tap(find.byKey(_row));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    final Uri mail = opened.single;
    expect(mail.scheme, 'mailto');
    expect(mail.path, 'nukhbaa.app@gmail.com');
    expect(mail.queryParameters, <String, String>{'subject': 'دعم نُخبة'});
    expect(mail.query, isNot(contains('+')));
    expect(
      find.byKey(const Key('account.contactDeveloper.failed')),
      findsNothing,
    );
  });

  testWidgets('a mail nothing could open is said, with the address', (
    tester,
  ) async {
    final List<Uri> opened = await _pump(tester, opens: false);

    await tester.tap(find.byKey(_row));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(
      find.byKey(const Key('account.contactDeveloper.failed')),
      findsOneWidget,
    );
    expect(
      find.text('تعذّر فتح تطبيق البريد، راسلنا على nukhbaa.app@gmail.com'),
      findsOneWidget,
    );
  });

  testWidgets('the row holds at text x2 on a 360px phone', (tester) async {
    await _pump(tester, textScale: 2, size: const Size(360, 4000));

    expect(find.byKey(_row), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
