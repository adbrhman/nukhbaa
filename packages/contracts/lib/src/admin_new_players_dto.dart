import 'package:contracts/src/admin_dto.dart';

/// One player in `GET /admin/new-players` (script 202).
final class NewPlayerDto {
  /// Creates the line.
  const NewPlayerDto({
    required this.user,
    required this.joinedAt,
    required this.phoneAccounts,
    required this.predictions,
    this.nameHint,
  });

  /// Deserializes from a JSON map.
  factory NewPlayerDto.fromJson(Map<String, Object?> json) {
    return NewPlayerDto(
      user: UserSummaryDto.fromJson(json['user']! as Map<String, Object?>),
      joinedAt: DateTime.parse(json['joined_at']! as String).toUtc(),
      phoneAccounts: (json['phone_accounts'] as int?) ?? 0,
      predictions: (json['predictions'] as int?) ?? 0,
      nameHint: json['name_hint'] as String?,
    );
  }

  /// The account.
  final UserSummaryDto user;

  /// When the account was created (UTC).
  final DateTime joinedAt;

  /// The most accounts seen on any of his phones; 0 when none was seen.
  final int phoneAccounts;

  /// Every prediction he sent.
  final int predictions;

  /// Why the name may not be a real one: `automatic`, `digits`,
  /// `one_word`, `title` or `latin`; null when nothing points that way.
  final String? nameHint;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'joined_at': joinedAt.toUtc().toIso8601String(),
    'phone_accounts': phoneAccounts,
    'predictions': predictions,
    if (nameHint != null) 'name_hint': nameHint,
  };

  @override
  bool operator ==(Object other) =>
      other is NewPlayerDto &&
      other.user == user &&
      other.joinedAt == joinedAt &&
      other.phoneAccounts == phoneAccounts &&
      other.predictions == predictions &&
      other.nameHint == nameHint;

  @override
  int get hashCode =>
      Object.hash(user, joinedAt, phoneAccounts, predictions, nameHint);
}

/// The wire shape of `GET /admin/new-players?days=`: the players who joined
/// in the last [days] days, newest first.
final class NewPlayersDto {
  /// Creates the DTO.
  const NewPlayersDto({
    required this.days,
    required this.players,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory NewPlayersDto.fromJson(Map<String, Object?> json) {
    return NewPlayersDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      days: (json['days'] as int?) ?? 7,
      players: [
        for (final player in json['players']! as List<Object?>)
          NewPlayerDto.fromJson(player! as Map<String, Object?>),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The window read, in days.
  final int days;

  /// The players, newest first.
  final List<NewPlayerDto> players;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'days': days,
    'players': [for (final player in players) player.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! NewPlayersDto ||
        other.schemaVersion != schemaVersion ||
        other.days != days ||
        other.players.length != players.length) {
      return false;
    }
    for (var i = 0; i < players.length; i++) {
      if (other.players[i] != players[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, days, Object.hashAll(players));
}
