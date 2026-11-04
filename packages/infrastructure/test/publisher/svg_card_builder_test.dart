import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  final hilal = ClubBadge.ofColour(clubName: 'الهلال', fill: '#0B4FD8');
  final nassr = ClubBadge.ofColour(clubName: 'النصر', fill: '#F5D000');

  CardSpec goal({String? scorer = 'سالم الدوسري', String? minute = '45+2'}) =>
      CardSpec(
        kind: CardKind.goal,
        league: 'دوري روشن السعودي',
        headline: 'هدف التقدم',
        homeName: 'الهلال',
        awayName: 'النصر',
        homeBadge: hilal,
        awayBadge: nassr,
        score: const ScoreLine(2, 1),
        scoringHome: true,
        scorer: scorer,
        minuteLabel: minute,
      );

  test('a goal card is a 1080x1350 SVG in the bundled Arabic font', () {
    final svg = SvgCardBuilder.build(goal());

    expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
    expect(svg, contains('width="1080" height="1350"'));
    expect(svg, contains('font-family="IBM Plex Sans Arabic"'));
    expect(svg, endsWith('</svg>'));
  });

  test('each score and the minute are texts of their own, left to right', () {
    final svg = SvgCardBuilder.build(goal());

    // resvg reorders digits inside an Arabic run: never put them in one.
    expect(svg, contains('direction="ltr">2</text>'));
    expect(svg, contains('direction="ltr">1</text>'));
    expect(svg, contains("direction=\"ltr\">45+2'</text>"));
    expect(svg, isNot(contains('الدقيقة 45')));
  });

  test('the home side stands on the right', () {
    final svg = SvgCardBuilder.build(goal());
    final home = svg.indexOf('fill="#0B4FD8"');
    final homeCircle = svg.lastIndexOf('<circle cx="', home);

    expect(svg.substring(homeCircle, home), contains('cx="830"'));
  });

  test('no crest: each club is a disc of its colour with its name', () {
    final svg = SvgCardBuilder.build(goal());

    expect(svg, isNot(contains('<image')));
    expect(svg, contains('>هلال</text>'));
    expect(svg, contains('fill="#F5D000"'));
  });

  test('a goal with no scorer known names the side that scored', () {
    final svg = SvgCardBuilder.build(goal(scorer: null, minute: null));

    expect(svg, contains('>الهلال</text>'));
    expect(svg, isNot(contains('الدقيقة')));
  });

  test('a final card lists the scorers of each side, at most four', () {
    final svg = SvgCardBuilder.build(
      CardSpec(
        kind: CardKind.finalResult,
        league: 'دوري روشن السعودي',
        headline: 'النتيجة النهائية',
        homeName: 'الهلال',
        awayName: 'النصر',
        homeBadge: hilal,
        awayBadge: nassr,
        score: const ScoreLine(5, 1),
        verdict: 'فوز الهلال',
        homeScorers: const <String>['أ|1', 'ب|2', 'ج|3', 'د|4', 'هـ|5'],
        awayScorers: const <String>['و|60'],
      ),
    );

    expect(svg, contains('>فوز الهلال</text>'));
    expect(svg, contains('>ج</text>'));
    expect(svg, isNot(contains('>د</text>')));
    expect(svg, contains('>…</text>'));
    expect(svg, contains("direction=\"ltr\">60'</text>"));
  });

  test('text is escaped and long names are cut', () {
    expect(SvgCardBuilder.escape('A & <B>'), 'A &amp; &lt;B&gt;');
    expect(SvgCardBuilder.clip('ريال مدريد', 20), 'ريال مدريد');
    expect(SvgCardBuilder.clip('أ' * 30, 10), '${'أ' * 9}…');
    expect(SvgCardBuilder.badgeFontSize('هلال'), 64);
    expect(SvgCardBuilder.badgeFontSize('ريال مدريد'), 36);
  });
}
