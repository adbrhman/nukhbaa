/// The hero of the day through the real predictions board, the real reaction
/// sheet, the real `GET /me` and a fake server: the one player who alone
/// called a finished match exactly is named above the table for an admin
/// and marked in the cell, and tapping that prediction opens the card to
/// share. Another player is not shown any of it, the hero himself sees his
/// own (2026-10-24), an exact double makes the professional hero of the day
/// (2026-10-27), and a match two players called exactly has no hero. The
/// server pays the one exact call 6, 9 on the double (script 159), and the
/// card and its share text show those points.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/team_identity.dart';
import 'package:mobile/features/fixture_prediction/widgets/day_hero_card.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

String _hoursAgo(int hours) =>
    DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String();

Map<String, Object?> _prediction(
  String participantId,
  String name,
  int h, {
  bool isDouble = false,
}) => FixturePredictionDto(
  id: 'pr-$participantId',
  participantId: participantId,
  fixtureId: 'f-1',
  submittedAt: '2026-10-07T12:00:00.000Z',
  homeGoals: h,
  awayGoals: 0,
  isDouble: isDouble,
  displayName: name,
).toJson();

ParticipantFixtureScoreDto _score(
  String participantId,
  String grade, {
  bool doubled = false,
  bool alone = false,
}) => ParticipantFixtureScoreDto(
  fixtureId: 'f-1',
  participantId: participantId,
  rulesetVersion: 4,
  grade: grade,
  points: grade == 'exact_scoreline' ? (doubled ? 6 : 3) + (alone ? 3 : 0) : 0,
);

/// A finished match, Slovakia 4-0 Moldova. Sara called 4-0; Ahmad (the
/// viewer) called 1-0, unless [twoExact], when he called 4-0 too. With
/// [saraViews] Sara is the viewer; with [saraDouble] her 4-0 was her double.
final class _Server {
  _Server({
    required this.role,
    this.twoExact = false,
    this.saraViews = false,
    this.saraDouble = false,
  });

  final String role;
  final bool twoExact;
  final bool saraViews;
  final bool saraDouble;
  final String kickoffAt = _hoursAgo(3);

  Future<http.Response> handle(http.Request request) async {
    switch (request.url.path) {
      case '/me':
        return okJsonObject(
          MeResponseDto(
            user: AuthenticatedUserDto(
              userId: 'u-1',
              role: role,
              status: 'active',
              displayName: saraViews ? 'Sara' : 'Ahmad',
            ),
          ).toJson(),
        );
      case '/feed/current-month-fixtures':
        return okJsonList([
          CurrentMonthFixtureItemDto(
            competitionId: 'c-1',
            competitionName: 'League',
            seasonLabel: '10/2026',
            fixture: SeasonFixtureCardDto(
              seasonId: 's-1',
              fixtureId: 'f-1',
              homeTeam: 'Slovakia',
              awayTeam: 'Moldova',
              kickoffAt: kickoffAt,
            ),
          ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([
          saraViews
              ? _prediction('p-sara', 'Sara', 4, isDouble: saraDouble)
              : _prediction('p-me', 'Ahmad', twoExact ? 4 : 1),
        ]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([
          _prediction('p-me', 'Ahmad', twoExact ? 4 : 1),
          _prediction('p-sara', 'Sara', 4, isDouble: saraDouble),
        ]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(
          FixtureScoresDto(
            fixtureId: 'f-1',
            scores: <ParticipantFixtureScoreDto>[
              _score('p-me', twoExact ? 'exact_scoreline' : 'incorrect'),
              _score(
                'p-sara',
                'exact_scoreline',
                doubled: saraDouble,
                alone: !twoExact,
              ),
            ],
          ).toJson(),
        );
      case '/seasons/s-1/fixtures/f-1/reactions':
        return okJsonObject(
          const PredictionReactionsDto(
            reactions: <PredictionReactionTallyDto>[],
          ).toJson(),
        );
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pump(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

const Key _banner = Key('fixturePredictions.hero.f-1');
const Key _mark = Key('fixturePredictions.heroMark.f-1.p-sara');
const Key _share = Key('reactionSheet.shareHero');

void main() {
  testWidgets('an admin sees the hero and opens the card from the call', (
    tester,
  ) async {
    await _pump(tester, _Server(role: 'admin'));

    expect(find.byKey(_banner), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.textContaining('Sara'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_mark), findsOneWidget);
    expect(
      find.byKey(const Key('fixturePredictions.heroMark.f-1.p-me')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
    );
    await _frames(tester);
    expect(find.byKey(_share), findsOneWidget);

    await tester.tap(find.byKey(_share));
    await _frames(tester);
    final Finder card = find.byKey(const Key('dayHero.card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('بطاقة بطل اليوم للنخبة')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('dayHero.points')),
        matching: find.text('6 نقاط'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('dayHero.name'))).data,
      'Sara',
    );
    expect(find.byKey(const Key('dayHero.solo')), findsOneWidget);
    final Finder score = find.byKey(const Key('dayHero.score'));
    expect(
      find.descendant(of: score, matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: score, matching: find.text('0')),
      findsOneWidget,
    );
  });

  testWidgets('the banner opens the same card', (tester) async {
    await _pump(tester, _Server(role: 'admin'));

    await tester.tap(find.byKey(_banner));
    await _frames(tester);

    expect(find.byKey(const Key('dayHero.card')), findsOneWidget);
  });

  testWidgets('a player sees no hero and no card', (tester) async {
    await _pump(tester, _Server(role: 'user'));

    expect(find.byKey(_banner), findsNothing);
    expect(find.byKey(_mark), findsNothing);
    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
    );
    await _frames(tester);
    expect(find.byKey(const Key('reactionSheet')), findsOneWidget);
    expect(find.byKey(_share), findsNothing);
  });

  testWidgets('the hero sees his own and shares it', (tester) async {
    await _pump(tester, _Server(role: 'user', saraViews: true));

    expect(find.byKey(_banner), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.textContaining('حصلت على بطل اليوم للنخبة'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_mark), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
    );
    await _frames(tester);
    expect(find.byKey(_share), findsOneWidget);
    await tester.tap(find.byKey(_share));
    await _frames(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('dayHero.title'))).data,
      'بطاقة بطل اليوم للنخبة',
    );
    expect(find.byKey(const Key('dayHero.double')), findsNothing);
    expect(find.byKey(const Key('dayHero.share')), findsOneWidget);
  });

  testWidgets('an exact double is the professional hero of the day', (
    tester,
  ) async {
    await _pump(tester, _Server(role: 'admin', saraDouble: true));

    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.textContaining('البطل الاحترافي لليوم: Sara'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_banner));
    await _frames(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('dayHero.title'))).data,
      'بطاقة البطل الاحترافي لليوم',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('dayHero.double')),
        matching: find.text('مضاعفة · 9 نقاط'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dayHero.points')), findsNothing);
  });

  testWidgets('the professional hero sees his own under that name', (
    tester,
  ) async {
    await _pump(
      tester,
      _Server(role: 'user', saraViews: true, saraDouble: true),
    );

    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.textContaining('حصلت على البطل الاحترافي لليوم'),
      ),
      findsOneWidget,
    );
    // A player never sees the admins' doubles line, even his own.
    expect(
      find.byKey(const Key('fixturePredictions.doubles.f-1')),
      findsNothing,
    );
  });

  test('the share text names the match, the score and the points', () {
    DayHero hero({required bool isDouble, int? points}) => DayHero(
      fixtureId: 'f-1',
      participantId: 'p-1',
      playerName: 'عبد الرحمن المغربي',
      home: const ResolvedTeamIdentity(displayName: 'ليفربول'),
      away: const ResolvedTeamIdentity(displayName: 'أرسنال'),
      homeGoals: 2,
      awayGoals: 2,
      isDouble: isDouble,
      points: points,
    );

    expect(
      hero(isDouble: false, points: 6).shareMessage,
      'بطل اليوم للنخبة: عبد الرحمن المغربي، وحده أصاب مباراة '
      'ليفربول × أرسنال 2-2، وحصل على 6 نقاط.',
    );
    expect(
      hero(isDouble: true, points: 9).shareMessage,
      'البطل الاحترافي لليوم: عبد الرحمن المغربي، وحده أصاب نتيجة مباراة '
      'ليفربول × أرسنال 2-2 مضاعفة كما انتهت بالضبط، وحصل على 9 نقاط.',
    );
    expect(
      hero(isDouble: false).shareMessage,
      'بطل اليوم للنخبة: عبد الرحمن المغربي، وحده أصاب مباراة '
      'ليفربول × أرسنال 2-2.',
    );
  });

  testWidgets('two exact calls make no hero', (tester) async {
    await _pump(tester, _Server(role: 'admin', twoExact: true));

    expect(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
      findsOneWidget,
    );
    expect(find.byKey(_banner), findsNothing);
    expect(find.byKey(_mark), findsNothing);
  });
}
