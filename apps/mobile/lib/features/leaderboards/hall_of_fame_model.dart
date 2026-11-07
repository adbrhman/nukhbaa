/// What the Hall of Fame shows, worked out from the one list the server
/// already sends to every signed-in player (`GET /champions`).
///
/// Nothing here is stored or typed in by hand: the titles, the records and
/// the legends are all read off the crownings that already exist, so the hall
/// can never disagree with the crowned months.
library;

import 'package:contracts/contracts.dart';

/// A player enters the Legends with this many monthly titles.
const int kLegendTitles = 3;

/// A record only makes a legend once this many months have been crowned: with
/// one or two months on the books, "the record" is just whoever won them.
const int kLegendMinMonths = 3;

/// The records the hall keeps. Each is measured over crowned months.
enum HallRecordKind {
  /// The most points in one month.
  mostPoints,

  /// The most exact scorelines in one month.
  mostExact,

  /// The widest lead of a month's champion over the runner-up.
  biggestMargin,
}

/// One record, its value and everyone who holds it (a tie shares it).
final class HallRecord {
  /// Creates a record of [kind] worth [value], held by [holders].
  const HallRecord({
    required this.kind,
    required this.value,
    required this.holders,
  });

  /// Which record this is.
  final HallRecordKind kind;

  /// Points, exact scorelines or the lead, by [kind].
  final int value;

  /// The crownings that set it, so each carries its month and its player.
  final List<MonthChampionDto> holders;
}

/// A player and every month they were crowned.
final class HallTitleHolder {
  /// Creates a holder from [titles], newest first.
  const HallTitleHolder({required this.titles});

  /// Every crowning of this player, newest first. Never empty.
  final List<MonthChampionDto> titles;

  /// The newest crowning (name and picture are read from it).
  MonthChampionDto get latest => titles.first;

  /// The player.
  String get userId => latest.userId;

  /// How many months the player was crowned for.
  int get count => titles.length;
}

/// A player in the Legends and the reasons, all derived from the rules.
final class HallLegend {
  /// Creates a legend for [holder].
  const HallLegend({
    required this.holder,
    required this.byTitles,
    required this.records,
  });

  /// The player and the months they were crowned.
  final HallTitleHolder holder;

  /// True when the player reached [kLegendTitles] monthly titles.
  final bool byTitles;

  /// The records the player holds, when they count toward a legend.
  final List<HallRecordKind> records;
}

/// The whole hall, ready to draw.
final class HallOfFame {
  /// Creates the hall.
  const HallOfFame({
    required this.months,
    required this.holders,
    required this.records,
    required this.legends,
  });

  /// The crowned months, newest first; a month holds one champion, or two.
  final List<List<MonthChampionDto>> months;

  /// Players ordered by their number of titles.
  final List<HallTitleHolder> holders;

  /// The records that have a value.
  final List<HallRecord> records;

  /// Players who earned a place among the legends.
  final List<HallLegend> legends;

  /// True while no month has been crowned.
  bool get isEmpty => months.isEmpty;
}

/// The sporting season (September to August) that holds an instant.
final class SportingSeasonWindow {
  /// Creates the season that opens in September of [startYear].
  const SportingSeasonWindow(this.startYear);

  /// The season holding [instant], read in UTC.
  factory SportingSeasonWindow.at(DateTime instant) {
    final DateTime utc = instant.toUtc();
    return SportingSeasonWindow(utc.month >= 9 ? utc.year : utc.year - 1);
  }

  /// The year of the season's September.
  final int startYear;

  /// The year of the season's August, when its champion is crowned.
  int get endYear => startYear + 1;

  /// `2026/2027`.
  String get label => '$startYear/$endYear';
}

DateTime _crowned(MonthChampionDto c) =>
    DateTime.tryParse(c.crownedAt)?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _byTitles(HallTitleHolder a, HallTitleHolder b) {
  final int byCount = b.count.compareTo(a.count);
  if (byCount != 0) return byCount;
  // Equal titles: whoever was crowned first stands first.
  final int byFirst = _crowned(
    a.titles.last,
  ).compareTo(_crowned(b.titles.last));
  if (byFirst != 0) return byFirst;
  return a.userId.compareTo(b.userId);
}

HallRecord? _maxOf(
  HallRecordKind kind,
  List<MonthChampionDto> rows,
  int Function(MonthChampionDto) valueOf,
) {
  int best = 0;
  for (final MonthChampionDto c in rows) {
    if (valueOf(c) > best) best = valueOf(c);
  }
  if (best <= 0) return null;
  return HallRecord(
    kind: kind,
    value: best,
    holders: <MonthChampionDto>[
      for (final MonthChampionDto c in rows)
        if (valueOf(c) == best) c,
    ],
  );
}

HallRecord? _marginRecord(
  List<List<MonthChampionDto>> months,
  MonthChampionsDto dto,
) {
  int best = 0;
  final List<MonthChampionDto> holders = <MonthChampionDto>[];
  for (final List<MonthChampionDto> month in months) {
    // Two champions share a month only on a tie: there is no lead to measure.
    if (month.length != 1) continue;
    final MonthChampionDto champion = month.single;
    MonthPodiumDto? runnerUp;
    for (final MonthPodiumDto p in dto.podiumOf(champion.seasonId)) {
      if (p.place == 2) {
        runnerUp = p;
        break;
      }
    }
    if (runnerUp == null) continue;
    final int margin = champion.points - runnerUp.points;
    if (margin <= 0) continue;
    if (margin > best) {
      best = margin;
      holders
        ..clear()
        ..add(champion);
    } else if (margin == best) {
      holders.add(champion);
    }
  }
  if (best <= 0) return null;
  return HallRecord(
    kind: HallRecordKind.biggestMargin,
    value: best,
    holders: holders,
  );
}

/// Works the hall out of the crowned months in [dto].
HallOfFame buildHallOfFame(MonthChampionsDto dto) {
  final List<MonthChampionDto> rows = dto.champions;

  final Map<String, List<MonthChampionDto>> byMonth =
      <String, List<MonthChampionDto>>{};
  final Map<String, List<MonthChampionDto>> byUser =
      <String, List<MonthChampionDto>>{};
  for (final MonthChampionDto c in rows) {
    byMonth.putIfAbsent(c.seasonId, () => <MonthChampionDto>[]).add(c);
    byUser.putIfAbsent(c.userId, () => <MonthChampionDto>[]).add(c);
  }

  final List<List<MonthChampionDto>> months = byMonth.values.toList()
    ..sort((a, b) => _crowned(b.first).compareTo(_crowned(a.first)));

  final List<HallTitleHolder> holders = <HallTitleHolder>[
    for (final List<MonthChampionDto> titles in byUser.values)
      HallTitleHolder(
        titles: List<MonthChampionDto>.unmodifiable(
          List<MonthChampionDto>.of(titles)
            ..sort((a, b) => _crowned(b).compareTo(_crowned(a))),
        ),
      ),
  ]..sort(_byTitles);

  final List<HallRecord> records = <HallRecord>[
    ?_maxOf(HallRecordKind.mostPoints, rows, (c) => c.points),
    ?_maxOf(HallRecordKind.mostExact, rows, (c) => c.exactCount),
    ?_marginRecord(months, dto),
  ];

  final bool recordsCount = months.length >= kLegendMinMonths;
  final List<HallLegend> legends = <HallLegend>[];
  for (final HallTitleHolder holder in holders) {
    final bool byTitles = holder.count >= kLegendTitles;
    final List<HallRecordKind> held = recordsCount
        ? <HallRecordKind>[
            for (final HallRecord r in records)
              if (r.holders.any((c) => c.userId == holder.userId)) r.kind,
          ]
        : const <HallRecordKind>[];
    if (byTitles || held.isNotEmpty) {
      legends.add(
        HallLegend(holder: holder, byTitles: byTitles, records: held),
      );
    }
  }

  return HallOfFame(
    months: months,
    holders: holders,
    records: records,
    legends: legends,
  );
}
