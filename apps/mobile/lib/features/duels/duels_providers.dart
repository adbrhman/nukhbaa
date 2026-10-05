/// Providers of the Duels feature (migration 0090): the typed client, the
/// caller's challenges and duels, and the per-session record of which
/// fixtures already offered a challenge after a saved prediction.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// The typed Duels client over the shared transport.
final duelsApiProvider = Provider<DuelsApi>(
  (ref) => DuelsApi(ref.watch(apiTransportProvider)),
);

/// `GET /me/duels` -- the caller's open challenges and duels.
final myDuelsProvider = FutureProvider.autoDispose<MyDuelsDto>((ref) async {
  return switch (await ref.watch(duelsApiProvider).myDuels()) {
    Ok<MyDuelsDto>(:final value) => value,
    Err<MyDuelsDto>(:final error) => throw error,
  };
});

/// The fixtures that already offered "challenge a friend" in this session,
/// so the offer appears once per fixture and never on every auto-save.
class DuelOfferLog extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  /// Records [fixtureId]; true only the first time.
  bool claim(String fixtureId) {
    if (state.contains(fixtureId)) return false;
    state = <String>{...state, fixtureId};
    return true;
  }
}

/// See [DuelOfferLog].
final duelOfferLogProvider = NotifierProvider<DuelOfferLog, Set<String>>(
  DuelOfferLog.new,
);
