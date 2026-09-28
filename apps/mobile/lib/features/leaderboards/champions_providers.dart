/// The champions of the monthly contests (migration 0077), for the
/// leaderboard's celebration, the crown beside a champion's name and the
/// champions' record.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// `GET /champions` -- every crowned champion, newest crowning first.
///
/// Not auto-disposed: the leaderboard tab stays alive, and the month board's
/// pull to refresh invalidates it, so a crowning made while the app is open
/// shows up with the next pull.
final monthChampionsProvider = FutureProvider<MonthChampionsDto>((ref) async {
  final LeaderboardsApi api = ref.watch(leaderboardsApiProvider);
  return switch (await api.champions()) {
    Ok<MonthChampionsDto>(:final value) => value,
    Err<MonthChampionsDto>(:final error) => throw error,
  };
});

/// Everyone ever crowned, by user id -- the crown beside a name. Empty while
/// the list loads or when it failed: a missing crown is a decoration left
/// out, never an error on a board.
final championUserIdsProvider = Provider<Set<String>>((ref) {
  final MonthChampionsDto? list = ref.watch(monthChampionsProvider).value;
  if (list == null) return const <String>{};
  return <String>{for (final MonthChampionDto c in list.champions) c.userId};
});

/// The champions whose celebration is running at [nowUtc]: those of the
/// newest crowning, for the 48 hours the server set (`celebrate_until`).
/// Empty otherwise.
List<MonthChampionDto> celebratingChampions(
  MonthChampionsDto? list,
  DateTime nowUtc,
) {
  if (list == null || list.champions.isEmpty) return const <MonthChampionDto>[];
  final MonthChampionDto newest = list.champions.first;
  final DateTime? until = DateTime.tryParse(newest.celebrateUntil)?.toUtc();
  if (until == null || !nowUtc.isBefore(until)) {
    return const <MonthChampionDto>[];
  }
  return <MonthChampionDto>[
    for (final MonthChampionDto c in list.champions)
      if (c.seasonId == newest.seasonId) c,
  ];
}
