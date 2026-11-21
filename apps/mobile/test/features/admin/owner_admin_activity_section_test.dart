/// Script 300: «سجل المشرفين» on the owners' page -- each change in words, with
/// the admin's name and the player or match it touched.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/screens/sections/owner_admin_activity_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

const String _id = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';

// NK300_14
void main() {
  test('each known change reads in words', () {
    expect(
      adminActivityLabel('POST', '/admin/users/$_id/display-name'),
      'تغيير اسم لاعب',
    );
    expect(
      adminActivityLabel('PUT', '/fixtures/$_id/result'),
      'تسجيل نتيجة مباراة',
    );
    expect(
      adminActivityLabel('POST', '/admin/h2h/seats'),
      'دوري المواجهات: المقاعد',
    );
    expect(adminActivityLabel('POST', '/new/thing'), contains('/new/thing'));
  });

  testWidgets('lists each change with the admin and the target', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ownerAdminActivityProvider.overrideWith(
            (ref) async => AdminActivityLogDto(
              entries: <AdminActivityDto>[
                AdminActivityDto(
                  id: 1,
                  actorName: 'خالد',
                  method: 'POST',
                  path: '/admin/users/$_id/display-name',
                  at: DateTime.utc(2026, 11, 21, 18),
                  target: 'سامي',
                ),
                AdminActivityDto(
                  id: 2,
                  actorName: 'خالد',
                  method: 'PUT',
                  path: '/fixtures/$_id/result',
                  at: DateTime.utc(2026, 11, 21, 17),
                  target: 'A × B',
                  result: '2-1',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: OwnerAdminActivitySection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تغيير اسم لاعب'), findsOneWidget);
    expect(find.text('المشرف: خالد'), findsNWidgets(2));
    expect(find.text('على: سامي'), findsOneWidget);
    expect(find.text('على: A × B · النتيجة الآن 2-1'), findsOneWidget);
    expect(find.textContaining('21:00'), findsOneWidget);
  });
}
