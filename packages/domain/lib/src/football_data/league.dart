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
    this.isContinental = false,
  });

  /// The league's canonical id.
  final LeagueRef id;

  /// The league's display name, as stored (Arabic, per the seed convention).
  final String name;

  /// A short code (e.g. "PL"), or `null` when none is on file.
  final String? shortName;

  /// The league's logo URL, or `null` when none is on file yet.
  final String? logoUrl;

  /// Whether this competition draws its entrants from other leagues.
  ///
  /// True for the Champions League, the Europa League and a domestic cup:
  /// their clubs are not their own, they are the clubs of the leagues
  /// that feed them. A caller offering teams for such a competition must
  /// offer the whole catalog rather than the rows tagged with this
  /// league's id -- tagging clubs here would mean a second Barcelona row,
  /// and a second crest to keep correct.
  ///
  /// Defaults to false: a plain domestic league is the common case, and a
  /// league with no flag on file behaves exactly as it did before.
  final bool isContinental;
}
