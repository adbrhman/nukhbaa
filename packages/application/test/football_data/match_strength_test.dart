import 'package:application/application.dart';
import 'package:test/test.dart';

// Script 189: the owner's examples of 2026-11-01 on a 20-club table.
TablePlace _at(int position) => TablePlace(position: position, tableSize: 20);

int _score(
  TablePlace? home,
  TablePlace? away, {
  bool homeIsBig = false,
  bool awayIsBig = false,
  bool isDerby = false,
}) => scoreMatch(
  home: home,
  away: away,
  homeIsBig: homeIsBig,
  awayIsBig: awayIsBig,
  isDerby: isDerby,
).total;

void main() {
  test('a place is worth 25 for the leader down to none for the last', () {
    const weights = MatchStrengthWeights();
    expect(placePoints(_at(1), weights), 25);
    expect(placePoints(_at(2), weights), 24);
    expect(placePoints(_at(6), weights), 18);
    expect(placePoints(_at(20), weights), 0);
    // No table read: half, neither rewarded nor punished.
    expect(placePoints(null, weights), 12);
    // A League Cup club from below the Premier League.
    expect(
      placePoints(const TablePlace(position: 21, tableSize: 20), weights),
      0,
    );
  });

  test('the second against the third scores highest of the examples', () {
    final secondThird = _score(_at(2), _at(3));
    final firstSixth = _score(_at(1), _at(6));
    final firstEighth = _score(_at(1), _at(8));
    expect(secondThird, 24 + 22 + 9);
    expect(firstSixth, 25 + 18 + 5);
    expect(firstEighth, 25 + 16 + 3);
    expect(secondThird, greaterThan(firstSixth));
    // The first against the eighth is not dropped for being outside six.
    expect(firstEighth, greaterThan(_score(_at(10), _at(15))));
  });

  test('a derby outside the top six beats an ordinary match above it', () {
    final derby = _score(_at(9), _at(12), isDerby: true);
    expect(derby, 14 + 11 + 7 + 25);
    expect(derby, greaterThan(_score(_at(4), _at(6))));
  });

  test('big clubs add 10 each, at most 15 a match', () {
    expect(_score(_at(10), _at(11), homeIsBig: true), 13 + 12 + 9 + 10);
    expect(
      _score(_at(10), _at(11), homeIsBig: true, awayIsBig: true),
      13 + 12 + 9 + 15,
    );
  });

  test('closeness needs both clubs in the table', () {
    final noTable = scoreMatch(
      home: null,
      away: null,
      homeIsBig: false,
      awayIsBig: false,
      isDerby: false,
    );
    expect(noTable.total, 24);
    expect(noTable.reasons, hasLength(2));
  });

  test('every part is named in the reasons', () {
    final strength = scoreMatch(
      home: _at(1),
      away: _at(2),
      homeIsBig: true,
      awayIsBig: false,
      isDerby: true,
    );
    expect(strength.total, 25 + 24 + 10 + 25 + 9);
    expect(strength.reasons, hasLength(5));
    expect(strength.reasons.first, contains('1/20'));
  });
}
