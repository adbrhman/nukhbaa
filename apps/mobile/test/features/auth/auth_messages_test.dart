/// Batch 131: what the sign-in form and the error presenter tell a player.
/// M-01 -- a new account awaiting its email confirmation is told to open
/// its mail, as news, and the form moves to signing in. L-01 -- a new
/// password needs 8 characters, as on the reset screen. M-09 -- a refusal
/// of one action is not "your session is over". M-02 / L-10 -- the web
/// reset link is told apart from a sign-up confirmation, and the address
/// bar returns to the app's own page. Through the real [SessionGate] and
/// `AuthApi` over the auth harness's fake server.
library;

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/error/error_presenter.dart';
import 'package:mobile/core/platform/reset_url.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../support/auth_harness.dart';

Future<List<http.Request>> _openRegister(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final List<http.Request> registers = <http.Request>[];
  final harness = buildAuthHarness((request) async {
    if (request.url.path == '/auth/register') {
      registers.add(request);
      return errorEnvelope(
        400,
        'auth.confirmation_required',
        'أرسلنا رابط تأكيد إلى بريدك. افتحه، ثم ارجع وسجّل الدخول.',
      );
    }
    return okMe(sampleUser);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SessionGate(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signIn.tabRegister')));
  await tester.pumpAndSettle();
  return registers;
}

Future<void> _fill(WidgetTester tester, String password) async {
  await tester.enterText(find.byKey(const Key('signIn.nameField')), 'Khaled');
  await tester.enterText(
    find.byKey(const Key('signIn.emailField')),
    'k@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('signIn.passwordField')),
    password,
  );
  await tester.enterText(
    find.byKey(const Key('signIn.confirmPasswordField')),
    password,
  );
  await tester.ensureVisible(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an account awaiting its email confirmation is told so, as '
      'news, on the sign-in tab', (tester) async {
    final registers = await _openRegister(tester);

    await _fill(tester, 'secret-123');

    expect(registers, hasLength(1));
    expect(find.byKey(const Key('signIn.errorBanner')), findsNothing);
    final Finder info = find.byKey(const Key('signIn.infoBanner'));
    expect(info, findsOneWidget);
    expect(
      find.descendant(of: info, matching: find.textContaining('رابط تأكيد')),
      findsOneWidget,
    );
    expect(find.textContaining('auth.confirmation_required'), findsNothing);
    // Moved to signing in, the email kept for it.
    expect(find.byKey(const Key('signIn.nameField')), findsNothing);
    expect(find.text('k@example.com'), findsOneWidget);
  });

  testWidgets('a new password shorter than 8 characters is refused before '
      'it is sent', (tester) async {
    final registers = await _openRegister(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

    await _fill(tester, 'abc12');

    expect(registers, isEmpty);
    expect(find.text(l10n.passwordTooShort), findsOneWidget);
  });

  group('ErrorPresenter', () {
    test('a refused action keeps the session', () {
      final String text = ErrorPresenter.message(
        const AppError.authorization('group.not_a_member', 'not a member'),
      );
      expect(text, 'لا تملك صلاحية هذا الإجراء.');
    });

    test('a refused credential still ends it', () {
      expect(
        ErrorPresenter.message(
          const AppError.authorization('auth.token_expired', 'expired'),
        ),
        contains('انتهت جلستك'),
      );
      expect(
        ErrorPresenter.message(
          const AppError.authorization(apiErrorUnexpectedStatus, 'proxy'),
        ),
        contains('انتهت جلستك'),
      );
    });

    test('too many attempts says wait, not "check your connection"', () {
      expect(
        ErrorPresenter.message(
          const AppError.transient('request.rate_limited', 'slow down'),
        ),
        contains('انتظر دقيقة'),
      );
    });
  });

  group('the web reset link', () {
    test('a recovery link is a reset; a sign-up confirmation is not', () {
      expect(
        isPasswordResetUrl(
          Uri.parse(
            'https://nukhbaa.app/nukhbaa/#access_token=a.b.c&expires_in=3600'
            '&refresh_token=r&token_type=bearer&type=recovery',
          ),
        ),
        isTrue,
      );
      expect(
        isPasswordResetUrl(
          Uri.parse(
            'https://nukhbaa.app/nukhbaa/#access_token=a.b.c&expires_in=3600'
            '&refresh_token=r&token_type=bearer&type=signup',
          ),
        ),
        isFalse,
      );
      expect(
        isPasswordResetUrl(
          Uri.parse('https://nukhbaa.app/nukhbaa/reset-password'),
        ),
        isTrue,
      );
      expect(
        isPasswordResetUrl(Uri.parse('https://nukhbaa.app/nukhbaa/')),
        isFalse,
      );
    });

    test('after the reset the bar shows the app, never the landing page', () {
      expect(
        appPathAfterPasswordReset(
          Uri.parse('https://nukhbaa.app/nukhbaa/reset-password?x=1#t=2'),
        ),
        '/nukhbaa/',
      );
      expect(
        appPathAfterPasswordReset(
          Uri.parse(
            'https://nukhbaa.app/nukhbaa/#access_token=a&type=recovery',
          ),
        ),
        '/nukhbaa/',
      );
    });
  });
}
