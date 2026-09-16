import 'package:shared/shared.dart';

/// A fixture the sync created from a provider match that still has no
/// recorded result.
final class PendingProviderFixture {
  /// Creates the entry.
  const PendingProviderFixture({
    required this.fixtureId,
    required this.externalId,
    required this.kickoffAt,
    required this.leagueId,
  });

  /// The app's fixture id.
  final String fixtureId;

  /// The provider's match id.
  final String externalId;

  /// Kickoff, UTC.
  final DateTime kickoffAt;

  /// The app's league id stored on the schedule, if any.
  final String? leagueId;
}

/// Persistence the automatic provider sync needs beyond the existing
/// repositories: the identity map between provider ids and app ids
/// (`football_data.external_identity_map`), and the list of provider-created
/// fixtures still waiting for a result.
abstract interface class ProviderSyncStore {
  /// The app ids of [externalIds] in [table] (`team` or `fixture`) for
  /// [source], keyed by external id. Unmapped ids are simply absent.
  Future<Result<Map<String, String>>> canonicalIds({
    required String source,
    required String table,
    required List<String> externalIds,
  });

  /// Records that [externalId] in [source] is the app's [canonicalId] in
  /// [table]. Linking an already-linked external id is a no-op.
  Future<Result<void>> link({
    required String source,
    required String table,
    required String externalId,
    required String canonicalId,
  });

  /// Fixtures linked to [source] that kicked off in
  /// `[kickedOffFrom, kickedOffBefore)` and have no recorded result yet,
  /// earliest first.
  Future<Result<List<PendingProviderFixture>>> fixturesAwaitingResult({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  });
}
