/// Audit M-08: a group code typed on a phone keyboard arrives in lower case
/// with a stray space; the join screen sends it upper-cased, and a refusal
/// reads as a sentence, never a technical code. Through the real
/// [JoinGroupScreen], its controller and the real `GroupsApi`.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/groups/join_group_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

void main() {
  testWidgets('a lower-case code is sent upper-cased; an unknown one is '
      'explained', (tester) async {
    final List<http.Request> joins = <http.Request>[];
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/groups/join') {
        joins.add(request);
        return errorEnvelope(409, 'group.invite_invalid', 'not valid');
      }
      return okMe(sampleUser);
    }, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const JoinGroupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('joinGroup.codeField')),
    );
    expect(field.textCapitalization, TextCapitalization.characters);

    await tester.enterText(
      find.byKey(const Key('joinGroup.codeField')),
      ' abcdefghjk ',
    );
    await tester.tap(find.byKey(const Key('joinGroup.submit')));
    await tester.pumpAndSettle();

    final Map<String, Object?> body =
        jsonDecode(joins.single.body) as Map<String, Object?>;
    expect(body['invite_code'], 'ABCDEFGHJK');
    final Text error = tester.widget<Text>(
      find.byKey(const Key('joinGroup.error')),
    );
    expect(error.data, contains('لا توجد مجموعة بهذا الرمز'));
    expect(error.data, isNot(contains('group.invite_invalid')));
  });
}
