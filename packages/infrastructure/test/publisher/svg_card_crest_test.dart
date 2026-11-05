import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  final ClubBadge home = ClubBadge.ofColour(
    clubName: 'Home',
    fill: '#0B4FD8',
    label: 'HOM',
  );
  final ClubBadge away = ClubBadge.ofColour(
    clubName: 'Away',
    fill: '#F5D000',
    label: 'AWY',
  );
  const List<int> homePng = <int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3];
  const List<int> awayPng = <int>[0x89, 0x50, 0x4E, 0x47, 9, 8, 7];

  CardSpec spec({List<int>? homeCrest, List<int>? awayCrest}) => CardSpec(
    kind: CardKind.finalResult,
    league: 'League',
    headline: 'Final',
    homeName: 'Home',
    awayName: 'Away',
    homeBadge: home,
    awayBadge: away,
    score: const ScoreLine(3, 2),
    homeCrest: homeCrest,
    awayCrest: awayCrest,
  );

  test('a crest is embedded on a white disc in place of the colour', () {
    final String svg = SvgCardBuilder.build(spec(homeCrest: homePng));

    expect(
      svg,
      contains('xlink:href="data:image/png;base64,${base64Encode(homePng)}"'),
    );
    expect(svg, contains('<circle cx="830" cy="620" r="132" fill="#FFFFFF"'));
    expect(svg, isNot(contains('fill="#0B4FD8"')));
    expect(svg, isNot(contains('>HOM</text>')));
  });

  test('a club with no crest stays the disc of its colour', () {
    final String svg = SvgCardBuilder.build(spec(homeCrest: homePng));

    expect(svg, contains('fill="#F5D000"'));
    expect(svg, contains('>AWY</text>'));
    expect('<image'.allMatches(svg), hasLength(1));
  });

  test('both crests: the home one on the right, the away one on the left', () {
    final String svg = SvgCardBuilder.build(
      spec(homeCrest: homePng, awayCrest: awayPng),
    );

    final int homeAt = svg.indexOf(base64Encode(homePng));
    final int awayAt = svg.indexOf(base64Encode(awayPng));
    expect(homeAt, greaterThan(0));
    expect(awayAt, greaterThan(homeAt));
    expect(
      svg,
      contains('<image xmlns:xlink="http://www.w3.org/1999/xlink" x="735"'),
    );
    expect(
      svg,
      contains('<image xmlns:xlink="http://www.w3.org/1999/xlink" x="155"'),
    );
    expect('<image'.allMatches(svg), hasLength(2));
  });

  test('an empty crest is no crest', () {
    final String svg = SvgCardBuilder.build(spec(homeCrest: const <int>[]));

    expect(svg, isNot(contains('<image')));
    expect(svg, contains('>HOM</text>'));
  });
}
