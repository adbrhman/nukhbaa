/// A team's mark (script 266): the club's crest from the owner's list when
/// the phone holds it, the country's flag from the bundle, or else the
/// team's disc -- and the disc again the moment the crest leaves the list,
/// or while a card is captured to be shared.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/crests/club_crests.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/team_logo.dart';

import '../../support/team_marks.dart';

Widget _app(ClubCrests? crests, Widget logo) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) =>
      crests == null ? child! : ClubCrestScope(crests: crests, child: child!),
  home: Scaffold(body: Center(child: logo)),
);

const TeamLogo _arsenal = TeamLogo(
  displayName: 'أرسنال',
  size: 34,
  crestSlug: 'arsenal',
  brandColor: Colors.red,
);

const Key _crest = ValueKey<String>('teamLogo.crest.arsenal');

void main() {
  testWidgets('the crest the phone holds is drawn', (tester) async {
    final ClubCrests crests = await crestsHolding(<String>['arsenal']);
    addTearDown(crests.dispose);

    await tester.pumpWidget(_app(crests, _arsenal));

    expect(find.byKey(_crest), findsOneWidget);
  });

  testWidgets('without the crest, the team disc and its letters', (
    tester,
  ) async {
    final ClubCrests crests = await crestsHolding(<String>['chelsea']);
    addTearDown(crests.dispose);

    await tester.pumpWidget(_app(crests, _arsenal));

    expect(find.byKey(_crest), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('without crests at all (no scope), the disc', (tester) async {
    await tester.pumpWidget(_app(null, _arsenal));

    expect(find.byKey(_crest), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a card captured to be shared draws the disc, then the crest', (
    tester,
  ) async {
    final ClubCrests crests = await crestsHolding(<String>['arsenal']);
    addTearDown(crests.dispose);
    await tester.pumpWidget(_app(crests, _arsenal));

    crests.hideForSharing();
    await tester.pump();
    expect(find.byKey(_crest), findsNothing);

    crests.showAfterSharing();
    await tester.pump();
    expect(find.byKey(_crest), findsOneWidget);
  });

  testWidgets('a country draws its bundled flag', (tester) async {
    await tester.pumpWidget(
      _app(
        null,
        const TeamLogo(
          displayName: 'فنلندا',
          size: 34,
          assetPath: 'assets/flags/finland.png',
        ),
      ),
    );

    expect(
      find.byKey(
        const ValueKey<String>('teamLogo.asset.assets/flags/finland.png'),
      ),
      findsOneWidget,
    );
  });
}
