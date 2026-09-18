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

/// The job name the fixtures sync records its last successful run under.
const String fixturesSyncJob = 'fixtures';

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

  /// The id of a fixture already on the schedule for the same match --
  /// one an admin added by hand, or one another source created -- earliest
  /// first. Both sides matching (by team id or by normalised name) counts
  /// anywhere in `[from, to)`; a single side matching counts only within
  /// three hours of [kickoffAt], since a club cannot play twice that
  /// close, which catches a hand-typed spelling the catalog does not use.
  Future<Result<String?>> findExistingFixture({
    required String homeTeamId,
    required String awayTeamId,
    required String homeTeamName,
    required String awayTeamName,
    required DateTime kickoffAt,
    required DateTime from,
    required DateTime to,
  });

  /// Fixtures linked to [source] that kicked off in
  /// `[kickedOffFrom, kickedOffBefore)` and have no recorded result yet,
  /// earliest first.
  Future<Result<List<PendingProviderFixture>>> fixturesAwaitingResult({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  });

  /// When [job] last completed successfully, or null when it never has.
  Future<Result<DateTime?>> lastSyncAt(String job);

  /// Records that [job] completed successfully at [at].
  Future<Result<void>> markSyncAt(String job, DateTime at);
}
