/// The Hall of Fame **view** state — a read-only provider over the
/// platform-wide, all-time standings (mirrors `leaderboards_providers.dart`'s
/// season board exactly, aggregated across every season instead of scoped to
/// one).
library;

import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'hall_of_fame_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// `GET /leaderboard/hall-of-fame` — the platform-wide, all-time standings.
/// Visible to any authenticated user, unlike a season board.
@riverpod
Future<HallOfFameDto> hallOfFame(Ref ref) async {
  final api = ref.watch(leaderboardsApiProvider);
  return _unwrap(await api.hallOfFame());
}
