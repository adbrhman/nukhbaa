import 'package:contracts/src/admin_dto.dart';

/// One account of a person in `GET /admin/person-links` (script 263).
final class LinkedAccountDto {
  /// Creates the line.
  const LinkedAccountDto({
    required this.user,
    required this.counted,
    required this.hidden,
  });

  /// Deserializes from a JSON map.
  factory LinkedAccountDto.fromJson(Map<String, Object?> json) {
    return LinkedAccountDto(
      user: UserSummaryDto.fromJson(json['user']! as Map<String, Object?>),
      counted: (json['counted'] as bool?) ?? false,
      hidden: (json['hidden'] as bool?) ?? false,
    );
  }

  /// The account.
  final UserSummaryDto user;

  /// Whether it counts on the boards: the main account and the second.
  final bool counted;

  /// Whether it is hidden now.
  final bool hidden;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'counted': counted,
    'hidden': hidden,
  };

  @override
  bool operator ==(Object other) =>
      other is LinkedAccountDto &&
      other.user == user &&
      other.counted == counted &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(user, counted, hidden);
}

/// One person: the main account's id and every account, the main first.
final class LinkedPersonDto {
  /// Creates the person.
  const LinkedPersonDto({required this.mainId, required this.accounts});

  /// Deserializes from a JSON map.
  factory LinkedPersonDto.fromJson(Map<String, Object?> json) {
    return LinkedPersonDto(
      mainId: json['main_id']! as String,
      accounts: [
        for (final account in json['accounts']! as List<Object?>)
          LinkedAccountDto.fromJson(account! as Map<String, Object?>),
      ],
    );
  }

  /// The main account's id.
  final String mainId;

  /// The accounts, the main one first, then the counted.
  final List<LinkedAccountDto> accounts;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'main_id': mainId,
    'accounts': [for (final account in accounts) account.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! LinkedPersonDto ||
        other.mainId != mainId ||
        other.accounts.length != accounts.length) {
      return false;
    }
    for (var i = 0; i < accounts.length; i++) {
      if (other.accounts[i] != accounts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(mainId, Object.hashAll(accounts));
}

/// The wire shape of `GET /admin/person-links` (script 263, migration
/// 0209): every person the owner admin linked. The owner admin alone reads
/// it.
final class PersonLinksDto {
  /// Creates the DTO.
  const PersonLinksDto({
    required this.people,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory PersonLinksDto.fromJson(Map<String, Object?> json) {
    return PersonLinksDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      people: [
        for (final person in json['people']! as List<Object?>)
          LinkedPersonDto.fromJson(person! as Map<String, Object?>),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The people.
  final List<LinkedPersonDto> people;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'people': [for (final person in people) person.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! PersonLinksDto ||
        other.schemaVersion != schemaVersion ||
        other.people.length != people.length) {
      return false;
    }
    for (var i = 0; i < people.length; i++) {
      if (other.people[i] != people[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(people));
}

/// The body of `PUT /admin/person-links/{mainId}`: the second account that
/// also counts (none when null) and the other accounts, which are hidden.
final class SetPersonRequestDto {
  /// Creates the request.
  const SetPersonRequestDto({required this.otherIds, this.secondId});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SetPersonRequestDto.fromJson(Map<String, Object?> json) {
    return SetPersonRequestDto(
      secondId: json['second_id'] as String?,
      otherIds: <String>[
        for (final Object? id
            in (json['other_ids'] as List<Object?>?) ?? const <Object?>[])
          if (id is String) id,
      ],
    );
  }

  /// The second account that counts, or null.
  final String? secondId;

  /// The accounts hidden from every board.
  final List<String> otherIds;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    if (secondId != null) 'second_id': secondId,
    'other_ids': otherIds,
  };
}
