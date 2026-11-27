/// The champions of the Elite Cup (migrations 0190 and 0204), for the admin's
/// crowning panel and the hall of fame.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// `GET /cup-champions` -- the champions of the cup, newest month first.
///
/// Auto-disposed: each visit to the panel or the hall of fame reads the
/// list again, so a title decided while the app was open shows up.
final cupChampionsProvider = FutureProvider.autoDispose<CupChampionsDto>((
  ref,
) async {
  final LeaderboardsApi api = ref.watch(leaderboardsApiProvider);
  return switch (await api.cupChampions()) {
    Ok<CupChampionsDto>(:final value) => value,
    Err<CupChampionsDto>(:final error) => throw error,
  };
});

/// How many days the champions of paths 2 and 3 stay in the hall of fame,
/// counted from the instant their title was decided (owner decision
/// 2026-11-27: 48 hours exactly).
const int kCupRunnerUpDays = 2;

/// The champions the hall of fame shows at [now]: path 1 always; path 2 and
/// path 3 only while `now - decidedAt` is under [kCupRunnerUpDays] days, so a
/// title decided exactly 48 hours ago is already gone. A missing or unreadable
/// `decided_at` hides the path (it fails closed); an instant in the future
/// shows it. The order is kept. The admin's crowning panel reads the whole
/// list and is not filtered.
List<CupChampionDto> visibleCupChampions(
  List<CupChampionDto> champions,
  DateTime now,
) {
  const Duration window = Duration(days: kCupRunnerUpDays);
  return <CupChampionDto>[
    for (final CupChampionDto c in champions)
      if (c.place == 1 || _decidedWithin(c.decidedAt, now, window)) c,
  ];
}

bool _decidedWithin(String? decidedAt, DateTime now, Duration window) {
  final DateTime? at = decidedAt == null ? null : DateTime.tryParse(decidedAt);
  return at != null && now.difference(at) < window;
}

/// The name of the cup of path [place] (1 to 3).
String cupPathName(int place) => switch (place) {
  1 => 'كأس النخبة',
  2 => 'كأس المسار الثاني',
  _ => 'كأس المسار الثالث',
};

/// How the title was won, in words.
String cupHowName(String how) =>
    how == 'walkover' ? 'تأهل بلا خصم في النهائي' : 'فاز في النهائي';

/// A cup month (`2026-11-01`) as the stored label (`11/2026`) the month
/// names are made from; the text as it is when it has another shape.
String cupMonthLabel(String monthStart) {
  final List<String> parts = monthStart.split('-');
  if (parts.length != 3) return monthStart;
  return '${parts[1]}/${parts[0]}';
}
