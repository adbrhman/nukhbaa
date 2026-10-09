/// Providers of the head-to-head league (migration 0100).
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// `GET /me/h2h-league` -- the caller's month: the group's table, every
/// round with the caller's match, and the zones. Computed by the server on
/// every call; nothing here sorts, sums or decides a result.
final myH2hLeagueProvider = FutureProvider.autoDispose<MyH2hLeagueDto>((
  ref,
) async {
  final AuthApi api = ref.watch(authApiProvider);
  return switch (await api.myH2hLeague()) {
    Ok<MyH2hLeagueDto>(:final value) => value,
    Err<MyH2hLeagueDto>(:final error) => throw error,
  };
});
