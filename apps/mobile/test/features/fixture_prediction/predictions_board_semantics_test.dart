/// What a screen reader hears on the predictions board, through the real
/// page and a fake server (Accessibility Scanner, 2026-10-28): every
/// prediction is one button named by its player and its match, never the
/// bare score many cells share; a match header reads "home vs away" once,
/// never the cross between them alone; and a row is a full 48 dp target.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const String _vs = 'ضد';

String _hoursAgo(int hours) =>
    DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String();

const List<String> _fixtures = <String>['f-1', 'f-2'];
const int _playerCount = 3;

/// Every player calls the same 2 - 1 on every match: the score alone
/// cannot tell one cell from another.
Map<String, Object?> _prediction(String fixtureId, int i) =>
    FixturePredictionDto(
      id: 'pr-$fixtureId-$i',
      participantId: 'p-$i',
      fixtureId: fixtureId,
      submittedAt: '2026-10-27T12:00:00.000Z',
      homeGoals: 2,
      awayGoals: 1,
      isDouble: false,
      displayName: 'Player $i',
    ).toJson();

final class _Server {
  final String kickoffAt = _hoursAgo(3);

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    final RegExpMatch? fixture = RegExp(
      r'^/seasons/s-1/fixtures/([^/]+)/(predictions|scores|reactions)$',
    ).firstMatch(path);
    if (fixture != null) {
      final String id = fixture.group(1)!;
      switch (fixture.group(2)) {
        case 'predictions':
          return okJsonList([
            for (int i = 0; i < _playerCount; i++) _prediction(id, i),
          ]);
        case 'scores':
          return okJsonObject(
            FixtureScoresDto(
              fixtureId: id,
              scores: const <ParticipantFixtureScoreDto>[],
            ).toJson(),
          );
        case 'reactions':
          return okJsonObject(
            const PredictionReactionsDto(
              reactions: <PredictionReactionTallyDto>[],
            ).toJson(),
          );
      }
    }
    switch (path) {
      case '/me':
        return okJsonObject(
          const MeResponseDto(
            user: AuthenticatedUserDto(
              userId: 'u-9',
              role: 'player',
              status: 'active',
              displayName: 'Viewer',
            ),
          ).toJson(),
        );
      case '/feed/current-month-fixtures':
        return okJsonList([
          for (int i = 0; i < _fixtures.length; i++)
            CurrentMonthFixtureItemDto(
              competitionId: 'c-1',
              competitionName: 'League',
              seasonLabel: '10/2026',
              fixture: SeasonFixtureCardDto(
                seasonId: 's-1',
                fixtureId: _fixtures[i],
                homeTeam: 'Home ${i + 1}',
                awayTeam: 'Away ${i + 1}',
                kickoffAt: kickoffAt,
              ),
            ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList(const []);
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pump(WidgetTester tester) async {
  // A 360 x 800 phone.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final _Server server = _Server();
  final harness = buildCurrentMonthFixturesHarness(server.handle);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: FixturePredictionsBoardPage(kickoffAt: server.kickoffAt),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Finder _cell(String fixtureId, int player) =>
    find.byKey(Key('fixturePredictions.cell.$fixtureId.p-$player'));

/// The node a match header is read as: the one its drawn names sit in.
SemanticsNode _header(WidgetTester tester, String fixtureId) =>
    tester.getSemantics(
      find
          .descendant(
            of: find.byKey(Key('fixturePredictions.header.$fixtureId')),
            matching: find.byType(Text),
          )
          .first,
    );

void main() {
  testWidgets('each match header reads home vs away once, never the cross '
      'alone', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await _pump(tester);
      for (final String id in _fixtures) {
        final String label = _header(tester, id).label;
        expect(label, contains(' $_vs '), reason: id);
        expect(label, isNot(contains('×')), reason: id);
      }
      expect(_header(tester, 'f-1').label, isNot(_header(tester, 'f-2').label));
      expect(find.bySemanticsLabel(RegExp(r'^\s*×\s*$')), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('every prediction is one button named by its player and its '
      'match, so no two cells read alike', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await _pump(tester);
      final Map<String, String> labels = <String, String>{};
      final Set<int> ids = <int>{};
      for (final String id in _fixtures) {
        final String match = _header(tester, id).label;
        for (int i = 0; i < _playerCount; i++) {
          expect(_cell(id, i), findsOneWidget, reason: '$id p-$i');
          final SemanticsNode node = tester.getSemantics(_cell(id, i));
          expect(node.flagsCollection.isButton, isTrue, reason: '$id p-$i');
          expect(node.label, contains('Player $i'), reason: '$id p-$i');
          expect(node.label, contains(match), reason: '$id p-$i');
          expect(node.label, contains('2'), reason: '$id p-$i');
          labels['$id p-$i'] = node.label;
          ids.add(node.id);
        }
      }
      // Six cells, six nodes, six different names.
      expect(ids, hasLength(_fixtures.length * _playerCount));
      expect(
        labels.values.toSet(),
        hasLength(labels.length),
        reason: '$labels',
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('a row is a full 48 dp touch target', (tester) async {
    await _pump(tester);
    for (int i = 0; i < _playerCount; i++) {
      expect(
        tester.getSize(_cell('f-1', i)).height,
        greaterThanOrEqualTo(48),
        reason: 'p-$i cell',
      );
      expect(
        tester.getSize(find.byKey(Key('fixturePredictions.row.p-$i'))).height,
        greaterThanOrEqualTo(48),
        reason: 'p-$i name',
      );
    }
  });
}
