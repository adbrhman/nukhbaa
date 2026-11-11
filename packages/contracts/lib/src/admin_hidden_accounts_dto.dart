import 'package:contracts/src/admin_dto.dart';

/// One account in `GET /admin/hidden-accounts` (script 258): an account the
/// owner admin hid from every board.
final class HiddenAccountDto {
  /// Creates the line.
  const HiddenAccountDto({required this.user, required this.hiddenAt});

  /// Deserializes from a JSON map.
  factory HiddenAccountDto.fromJson(Map<String, Object?> json) {
    return HiddenAccountDto(
      user: UserSummaryDto.fromJson(json['user']! as Map<String, Object?>),
      hiddenAt: DateTime.parse(json['hidden_at']! as String).toUtc(),
    );
  }

  /// The account.
  final UserSummaryDto user;

  /// When it was hidden (UTC).
  final DateTime hiddenAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'hidden_at': hiddenAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is HiddenAccountDto &&
      other.user == user &&
      other.hiddenAt == hiddenAt;

  @override
  int get hashCode => Object.hash(user, hiddenAt);
}

/// The wire shape of `GET /admin/hidden-accounts` (script 258): the hidden
/// accounts, the most recently hidden first. The owner admin alone reads it.
final class HiddenAccountsDto {
  /// Creates the DTO.
  const HiddenAccountsDto({
    required this.accounts,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory HiddenAccountsDto.fromJson(Map<String, Object?> json) {
    return HiddenAccountsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      accounts: [
        for (final account in json['accounts']! as List<Object?>)
          HiddenAccountDto.fromJson(account! as Map<String, Object?>),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The accounts, the most recently hidden first.
  final List<HiddenAccountDto> accounts;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'accounts': [for (final account in accounts) account.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! HiddenAccountsDto ||
        other.schemaVersion != schemaVersion ||
        other.accounts.length != accounts.length) {
      return false;
    }
    for (var i = 0; i < accounts.length; i++) {
      if (other.accounts[i] != accounts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(accounts));
}
