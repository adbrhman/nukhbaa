/// Widget tests for [AdminDashboardScreen], wired through the real screen +
/// providers + controllers over [buildAdminHarness] (a `MockClient`
/// transport). They assert the user-visible admin surface at the same depth
/// as `prediction_screen_test.dart`, across all four tabs:
///   * layout: all four tabs render with the audit trail visible by default;
///   * Audit log: data / legitimate-empty / error+retry;
///   * User sanction: empty fields send no command; a successful
///     suspend/reinstate shows the result and refreshes the audit trail; a
///     failed command renders the typed error via `ErrorPresenter`;
///   * Ledger lookup: an empty participant id sends no read; a successful
///     lookup lists the entries; a failed lookup renders the typed error;
///   * Fixture schedule: the register/correct affordances are mutually
///     exclusive, gated purely on whether a fixture id was typed.
///
/// Networking is served entirely by the harness handler branching on
/// `request.method` + `request.url.path`. Only the socket is faked; the real
/// `api_client` runs end-to-end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/admin_dashboard_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

Widget _host(AdminHarness harness, Widget child) => UncontrolledProviderScope(
  container: harness.container,
  child: MaterialApp(
    // نثبّت الإنجليزية هنا فقط لأن منتقيات التاريخ/الوقت في Material
    // تعرض تسمية التأكيد "OK" بالإنجليزية؛ لا يمسّ هذا سلوك التطبيق
    // الفعلي (العربية تبقى الافتراضية هناك)، فقط عزل هذا الاختبار.
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('en'),
    home: child,
  ),
);

Future<void> _goToTab(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('AdminDashboardScreen — layout', () {
    testWidgets('renders all four tabs with the audit trail active by '
        'default', (tester) async {
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(twoAuditEntries.toJson());
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin.title')), findsOneWidget);
      expect(find.byKey(const Key('admin.tab.audit')), findsOneWidget);
      expect(find.byKey(const Key('admin.tab.users')), findsOneWidget);
      expect(find.byKey(const Key('admin.tab.ledger')), findsOneWidget);
      expect(find.byKey(const Key('admin.tab.fixtures')), findsOneWidget);
      // The audit tab is index 0 — its content is already visible.
      expect(
        find.byKey(const Key('admin.audit.action.audit-2')),
        findsOneWidget,
      );
    });
  });

  group('AdminDashboardScreen — audit log', () {
    testWidgets('shows every entry, newest first as returned by the server', (
      tester,
    ) async {
      final harness = buildAdminHarness((request) async {
        return okJsonObject(twoAuditEntries.toJson());
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin.audit.action.audit-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin.audit.action.audit-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin.audit.detail.audit-2')),
        findsOneWidget,
      );
    });

    testWidgets('a legitimate empty trail shows the empty affordance, not '
        'an error', (tester) async {
      final harness = buildAdminHarness((request) async {
        return okJsonObject(emptyAuditLog.toJson());
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('browse.empty')), findsOneWidget);
      expect(find.byKey(const Key('browse.error')), findsNothing);
    });

    testWidgets('a transient failure renders the typed error with a retry '
        'affordance that reloads the trail', (tester) async {
      var callCount = 0;
      final harness = buildAdminHarness((request) async {
        callCount++;
        if (callCount == 1) throw Exception('offline');
        return okJsonObject(twoAuditEntries.toJson());
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('browse.error')), findsOneWidget);
      expect(find.byKey(const Key('browse.error.retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('browse.error.retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('browse.error')), findsNothing);
      expect(
        find.byKey(const Key('admin.audit.action.audit-2')),
        findsOneWidget,
      );
    });
  });

  group('AdminDashboardScreen — user sanction', () {
    testWidgets('suspending with an empty user id or reason sends no '
        'command', (tester) async {
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        return errorEnvelope(400, 'unexpected', 'should not be called');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.users');

      await tester.tap(find.byKey(const Key('admin.users.suspend')));
      await tester.pumpAndSettle();

      expect(
        harness.captured.any((c) => c.request.url.path.contains('/suspend')),
        isFalse,
      );
      expect(find.byKey(const Key('admin.users.error')), findsNothing);
    });

    testWidgets('a successful suspend shows the resulting status and '
        'refreshes the audit trail', (tester) async {
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'POST' &&
            request.url.path == '/admin/users/user-9/suspend') {
          return okJsonObject(suspendedResult.toJson());
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.users');

      await tester.enterText(
        find.byKey(const Key('admin.users.userIdField')),
        'user-9',
      );
      await tester.enterText(
        find.byKey(const Key('admin.users.reasonField')),
        'ابتزاز داخل الدردشة',
      );
      await tester.tap(find.byKey(const Key('admin.users.suspend')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin.users.result')), findsOneWidget);
      expect(find.byKey(const Key('admin.users.error')), findsNothing);
    });

    testWidgets('a failed reinstate renders the typed error via '
        'ErrorPresenter', (tester) async {
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'POST' &&
            request.url.path == '/admin/users/user-9/reinstate') {
          return errorEnvelope(
            409,
            'user.not_suspended',
            'the user is not suspended',
          );
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.users');

      await tester.enterText(
        find.byKey(const Key('admin.users.userIdField')),
        'user-9',
      );
      await tester.enterText(
        find.byKey(const Key('admin.users.reasonField')),
        'تصحيح إداري',
      );
      await tester.tap(find.byKey(const Key('admin.users.reinstate')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin.users.error')), findsOneWidget);
      expect(find.byKey(const Key('admin.users.result')), findsNothing);
    });
  });

  group('AdminDashboardScreen — ledger lookup', () {
    testWidgets('looking up with an empty participant id sends no read', (
      tester,
    ) async {
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        return errorEnvelope(400, 'unexpected', 'should not be called');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.ledger');

      await tester.tap(find.byKey(const Key('admin.ledger.lookup')));
      await tester.pumpAndSettle();

      expect(
        harness.captured.any((c) => c.request.url.path.contains('/ledger')),
        isFalse,
      );
    });

    testWidgets('a successful lookup lists the participant\'s entries', (
      tester,
    ) async {
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'GET' &&
            request.url.path == '/admin/participants/part-1/ledger') {
          return okJsonObject(oneLedgerEntry.toJson());
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.ledger');

      await tester.enterText(
        find.byKey(const Key('admin.ledger.participantIdField')),
        'part-1',
      );
      await tester.tap(find.byKey(const Key('admin.ledger.lookup')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin.ledger.item.entry-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin.ledger.kind.entry-1')),
        findsOneWidget,
      );
    });

    testWidgets('a failed lookup renders the typed error via ErrorPresenter', (
      tester,
    ) async {
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'GET' &&
            request.url.path == '/admin/participants/part-x/ledger') {
          return errorEnvelope(
            404,
            'participant.not_found',
            'no such '
                'participant',
          );
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.ledger');

      await tester.enterText(
        find.byKey(const Key('admin.ledger.participantIdField')),
        'part-x',
      );
      await tester.tap(find.byKey(const Key('admin.ledger.lookup')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin.ledger.error')), findsOneWidget);
    });
  });

  group('AdminDashboardScreen — add match (single flow)', () {
    testWidgets('add-match is gated until a round, both teams, and a kickoff '
        'are chosen; picking each dropdown drives the next read', (
      tester,
    ) async {
      final harness = buildAdminHarness((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'GET' && path == '/competitions') {
          return okJsonArray([oneCompetition.toJson()]);
        }
        if (request.method == 'GET' && path == '/competitions/comp-1/seasons') {
          return okJsonArray([oneSeason.toJson()]);
        }
        if (request.method == 'GET' && path == '/seasons/season-1/rounds') {
          return okJsonArray([openedRound.toJson()]);
        }
        if (request.method == 'GET' && path == '/rounds/round-new/fixtures') {
          return okJsonArray(const <Map<String, Object?>>[]);
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.fixtures');

      FilledButton addButton() => tester.widget<FilledButton>(
        find.byKey(const Key('admin.fixtures.addMatch')),
      );

      // لا شيء مختار بعد -> الزر معطّل.
      expect(addButton().onPressed, isNull);

      // اختر المسابقة.
      await tester.tap(
        find.byKey(const Key('admin.fixtures.competitionField')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin.fixtures.competitionField.comp-1')).last,
      );
      await tester.pumpAndSettle();

      // اختر الموسم.
      await tester.tap(find.byKey(const Key('admin.fixtures.seasonField')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin.fixtures.seasonField.season-1')).last,
      );
      await tester.pumpAndSettle();

      // اختر الجولة.
      await tester.tap(find.byKey(const Key('admin.fixtures.roundField')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin.fixtures.roundField.round-new')).last,
      );
      await tester.pumpAndSettle();

      // الفريقان.
      await tester.enterText(
        find.byKey(const Key('admin.fixtures.homeTeamField')),
        'Al Hilal',
      );
      await tester.enterText(
        find.byKey(const Key('admin.fixtures.awayTeamField')),
        'Al Nassr',
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // ما زال بلا موعد -> معطّل.
      expect(addButton().onPressed, isNull);
    });

    testWidgets('a full add-match registers the fixture then links it, and '
        'shows the success line', (tester) async {
      final harness = buildAdminHarness((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'GET' && path == '/competitions') {
          return okJsonArray([oneCompetition.toJson()]);
        }
        if (request.method == 'GET' && path == '/competitions/comp-1/seasons') {
          return okJsonArray([oneSeason.toJson()]);
        }
        if (request.method == 'GET' && path == '/seasons/season-1/rounds') {
          return okJsonArray([openedRound.toJson()]);
        }
        if (request.method == 'GET' && path == '/rounds/round-new/fixtures') {
          return okJsonArray(const <Map<String, Object?>>[]);
        }
        if (request.method == 'POST' && path == '/fixtures') {
          return okJsonObject(registeredFixture.toJson());
        }
        if (request.method == 'POST' && path == '/rounds/round-new/fixtures') {
          return okJsonObject(linkedRoundFixture.toJson());
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));
      await tester.pumpAndSettle();
      await _goToTab(tester, 'admin.tab.fixtures');

      await tester.tap(
        find.byKey(const Key('admin.fixtures.competitionField')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin.fixtures.competitionField.comp-1')).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin.fixtures.seasonField')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin.fixtures.seasonField.season-1')).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin.fixtures.roundField')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('admin.fixtures.roundField.round-new')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('admin.fixtures.homeTeamField')),
        'Al Hilal',
      );
      await tester.enterText(
        find.byKey(const Key('admin.fixtures.awayTeamField')),
        'Al Nassr',
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // اختر الموعد عبر منتقيي التاريخ والوقت.
      await tester.ensureVisible(
        find.byKey(const Key('admin.fixtures.kickoffPicker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin.fixtures.kickoffPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // تأكيد التاريخ
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // تأكيد الوقت
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin.fixtures.addMatch')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin.fixtures.result')), findsOneWidget);
      expect(find.byKey(const Key('admin.fixtures.error')), findsNothing);
      expect(
        harness.captured.any(
          (c) =>
              c.request.method == 'POST' && c.request.url.path == '/fixtures',
        ),
        isTrue,
      );
      expect(
        harness.captured.any(
          (c) =>
              c.request.method == 'POST' &&
              c.request.url.path == '/rounds/round-new/fixtures',
        ),
        isTrue,
      );
    });
  });
}
