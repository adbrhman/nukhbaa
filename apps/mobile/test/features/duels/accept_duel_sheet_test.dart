/// The accept sheet waits for the caller's saved predictions (audit M-12):
/// nothing can be changed or sent before they load, a failed load says so
/// and offers a retry, and once loaded the sheet says the score it sends
/// becomes the caller's prediction.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/duels/accept_duel_sheet.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

const DuelChallengeDto _challenge = DuelChallengeDto(
  id: 'c-1',
  code: 'ABCDEFGHJKMN',
  seasonId: 's-1',
  fixtureId: 'f-1',
  homeTeam: 'Home FC',
  awayTeam: 'Away FC',
  kickoffAt: '2099-01-01T18:00:00.000Z',
  challengerUserId: 'rival',
  challengerName: 'Rival',
  isPrivate: false,
  capacity: 5,
  acceptedCount: 0,
  state: 'open',
  isMine: false,
  isForMe: false,
);

Future<void> _open(
  WidgetTester tester,
  AsyncValue<Map<String, FixturePredictionDto>> mine,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myFixturePredictionsByFixtureProvider.overrideWithValue(mine),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: AcceptDuelSheet(challenge: _challenge)),
      ),
    ),
  );
  await tester.pump();
}

VoidCallback? _onPressed(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed;

VoidCallback? _stepper(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(Key(key))).onPressed;

void main() {
  testWidgets('nothing can be changed or sent before the saved predictions '
      'load', (tester) async {
    await _open(
      tester,
      const AsyncLoading<Map<String, FixturePredictionDto>>(),
    );

    expect(_onPressed(tester, 'acceptDuel.accept'), isNull);
    expect(_stepper(tester, 'acceptDuel.home.increment'), isNull);
    expect(_stepper(tester, 'acceptDuel.away.increment'), isNull);
    expect(find.text('جارٍ تحميل توقعك…'), findsOneWidget);
    expect(find.byKey(const Key('acceptDuel.note')), findsNothing);
  });

  testWidgets('a failed load says so, offers a retry and still sends '
      'nothing', (tester) async {
    await _open(
      tester,
      AsyncError<Map<String, FixturePredictionDto>>(
        Exception('offline'),
        StackTrace.empty,
      ),
    );

    expect(find.byKey(const Key('acceptDuel.loadError')), findsOneWidget);
    expect(find.byKey(const Key('acceptDuel.retry')), findsOneWidget);
    expect(_onPressed(tester, 'acceptDuel.accept'), isNull);
    expect(_stepper(tester, 'acceptDuel.home.increment'), isNull);
  });

  testWidgets('once loaded, the saved score shows and accepting is '
      'possible', (tester) async {
    await _open(
      tester,
      const AsyncData<Map<String, FixturePredictionDto>>(
        <String, FixturePredictionDto>{
          'f-1': FixturePredictionDto(
            id: 'fp-1',
            participantId: 'p-1',
            fixtureId: 'f-1',
            submittedAt: '2026-10-05T10:00:00.000Z',
            homeGoals: 3,
            awayGoals: 2,
            isDouble: true,
          ),
        },
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('acceptDuel.home.value')),
        matching: find.text('3'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text('تغيير النتيجة هنا يغيّر توقعك المحفوظ لهذه المباراة.'),
      findsOneWidget,
    );
    expect(
      find.text('توقعك على هذه المباراة مضاعف، ويبقى كذلك.'),
      findsOneWidget,
    );
    expect(_onPressed(tester, 'acceptDuel.accept'), isNotNull);
    expect(_stepper(tester, 'acceptDuel.home.increment'), isNotNull);
  });

  testWidgets('with no saved prediction, the note says the score becomes '
      'the prediction', (tester) async {
    await _open(
      tester,
      const AsyncData<Map<String, FixturePredictionDto>>(
        <String, FixturePredictionDto>{},
      ),
    );

    expect(
      find.text('هذه النتيجة تُحفظ توقعَك لهذه المباراة.'),
      findsOneWidget,
    );
    expect(_onPressed(tester, 'acceptDuel.accept'), isNotNull);
    expect(find.byKey(const Key('acceptDuel.loadError')), findsNothing);
  });
}
