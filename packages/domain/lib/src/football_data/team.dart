import 'package:domain/src/football_data/team_ref.dart';

/// A canonical team identity (`football_data.teams`, migration
/// `0013_football_data.sql`): a provider-agnostic reference aggregate, never
/// a source of prediction/scoring truth. Populated today by admin-fed seed
/// data; [crestUrl] is `null` when no crest is on file yet — callers must
/// treat that as a legitimate state, not an error, and fall back to a letter
/// placeholder (never a blank space).
final class Team {
  /// Creates a team identity.
  const Team({
    required this.id,
    required this.name,
    required this.shortName,
    required this.crestUrl,
  });

  /// The team's canonical id.
  final TeamRef id;

  /// The team's display name, as stored (Arabic, per the current seed data
  /// convention — Football Data carries no locale distinction).
  final String name;

  /// A short code/abbreviation (e.g. "RMA"), or `null` when none is on file.
  final String? shortName;

  /// The team's crest image URL, or `null` when none is on file yet.
  final String? crestUrl;

  @override
  bool operator ==(Object other) =>
      other is Team &&
      other.id == id &&
      other.name == name &&
      other.shortName == shortName &&
      other.crestUrl == crestUrl;

  @override
  int get hashCode => Object.hash(id, name, shortName, crestUrl);

  @override
  String toString() => 'Team(${id.value}, $name)';
}
