/// How strong a match is, from its clubs' places in their league table
/// (decided by the owner on 2026-11-01, script 189).
///
/// Pure arithmetic: no clock, no database, no provider. The daily selection
/// ranks the matches it may add by [scoreMatch]; the parts of the score are
/// kept as [MatchStrength.reasons], so every choice can be read back and the
/// weights tuned after the trial week.
library;

/// A club's place in its league table. A [position] above [tableSize] is a
/// club outside the table (a League Cup club from below the Premier League).
final class TablePlace {
  /// Creates the place.
  const TablePlace({required this.position, required this.tableSize});

  /// 1 for the leader.
  final int position;

  /// How many clubs the table holds.
  final int tableSize;

  /// Whether the club is in the table at all.
  bool get inTable => position >= 1 && position <= tableSize;
}

/// The weights of [scoreMatch]: the owner's start of 2026-11-01, to be tuned
/// from the trial week's log.
final class MatchStrengthWeights {
  /// Creates the weights.
  const MatchStrengthWeights({
    this.placePerClub = 25,
    this.bigClub = 10,
    this.bigClubCap = 15,
    this.derby = 25,
    this.closeness = 10,
  });

  /// What one club's place is worth at most: the leader gets all of it, the
  /// last club none, the others in proportion.
  final int placePerClub;

  /// Added for each club of the big-clubs list, whatever its place.
  final int bigClub;

  /// The most the big-clubs part adds to one match.
  final int bigClubCap;

  /// Added when the match is one of the derbies.
  final int derby;

  /// The most the closeness part adds: this, less the gap between the two
  /// places, never below zero. Only when both clubs are in the table.
  final int closeness;
}

/// The score of one match and how it was made.
final class MatchStrength {
  /// Creates the score.
  const MatchStrength({required this.total, required this.reasons});

  /// The sum of the parts.
  final int total;

  /// One line per part, in Arabic, for the selection log.
  final List<String> reasons;
}

/// What [place] is worth under [weights]: the leader [placePerClub], the
/// last club none, a club outside the table none. A club with no known place
/// (no table could be read) gets half, neither rewarded nor punished.
int placePoints(TablePlace? place, MatchStrengthWeights weights) {
  final full = weights.placePerClub;
  if (place == null) {
    return full ~/ 2;
  }
  if (!place.inTable) {
    return 0;
  }
  if (place.tableSize <= 1) {
    return full;
  }
  final value =
      (full * (place.tableSize - place.position) / (place.tableSize - 1))
          .round();
  return value < 0 ? 0 : (value > full ? full : value);
}

/// Scores the match of [home] against [away] (their places, null when no
/// table could be read).
MatchStrength scoreMatch({
  required TablePlace? home,
  required TablePlace? away,
  required bool homeIsBig,
  required bool awayIsBig,
  required bool isDerby,
  MatchStrengthWeights weights = const MatchStrengthWeights(),
}) {
  final reasons = <String>[];
  var total = 0;

  final homePoints = placePoints(home, weights);
  final awayPoints = placePoints(away, weights);
  total += homePoints + awayPoints;
  reasons
    ..add('المضيف ${_where(home)}: $homePoints')
    ..add('الضيف ${_where(away)}: $awayPoints');

  final bigCount = (homeIsBig ? 1 : 0) + (awayIsBig ? 1 : 0);
  if (bigCount > 0) {
    var big = bigCount * weights.bigClub;
    if (big > weights.bigClubCap) {
      big = weights.bigClubCap;
    }
    total += big;
    reasons.add('أندية كبيرة ($bigCount): +$big');
  }

  if (isDerby) {
    total += weights.derby;
    reasons.add('ديربي: +${weights.derby}');
  }

  if (home != null && away != null && home.inTable && away.inTable) {
    final gap = (home.position - away.position).abs();
    final close = weights.closeness - gap;
    if (close > 0) {
      total += close;
      reasons.add('تقارب المستوى: +$close');
    }
  }

  return MatchStrength(total: total, reasons: reasons);
}

String _where(TablePlace? place) {
  if (place == null) {
    return 'بلا ترتيب';
  }
  if (!place.inTable) {
    return 'خارج الجدول';
  }
  return '${place.position}/${place.tableSize}';
}
