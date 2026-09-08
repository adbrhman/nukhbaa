import 'package:domain/src/football_data/league_ref.dart';

/// A league's display identity: a name, an optional short code, an optional
/// logo -- and nothing else (migration 0027).
///
/// Deliberately as thin as [Team]. A league here is what a fixture is labelled
/// with, not a competition with editions, tables and rules; the platform's own
/// contest is the calendar month, and modelling league seasons would invent
/// structure nothing reads.
final class League {
  /// Creates a league identity.
  const League({
    required this.id,
    required this.name,
    required this.shortName,
    required this.logoUrl,
  });

  /// The league's canonical id.
  final LeagueRef id;

  /// The league's display name, as stored (Arabic, per the seed convention).
  final String name;

  /// A short code (e.g. "PL"), or `null` when none is on file.
  final String? shortName;

  /// The league's logo URL, or `null` when none is on file yet.
  final String? logoUrl;
}
