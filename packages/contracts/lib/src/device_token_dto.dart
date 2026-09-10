/// Request body of `POST /me/device-token`.
///
/// The owner is deliberately absent: the server binds it from the verified
/// bearer token, never a body field (Security ADR §2), so a caller cannot
/// point another account's notifications at their own handset.
final class DeviceTokenRegistrationRequestDto {
  /// Creates the registration request.
  const DeviceTokenRegistrationRequestDto({
    required this.token,
    required this.platform,
  });

  /// Deserializes from a JSON map.
  factory DeviceTokenRegistrationRequestDto.fromJson(
    Map<String, Object?> json,
  ) {
    return DeviceTokenRegistrationRequestDto(
      token: json['token']! as String,
      platform: json['platform']! as String,
    );
  }

  /// The FCM registration token of the calling device.
  final String token;

  /// One of `RegisterDeviceToken.supportedPlatforms` (`android` | `ios`).
  final String platform;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'token': token, 'platform': platform};

  @override
  bool operator ==(Object other) =>
      other is DeviceTokenRegistrationRequestDto &&
      other.token == token &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(token, platform);
}

/// Response body of `POST /me/device-token`.
///
/// Carries no echo of the token: the client already has it, and a delivery
/// address has no reason to travel back over the wire.
final class DeviceTokenAckDto {
  /// Creates the acknowledgement.
  const DeviceTokenAckDto({
    required this.registered,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory DeviceTokenAckDto.fromJson(Map<String, Object?> json) {
    return DeviceTokenAckDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      registered: json['registered']! as bool,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Always `true` on a 200 -- the upsert is unconditional, so there is no
  /// meaningful `false`. The field exists so the body is a JSON object the
  /// client parses like every other response, not an empty special case.
  final bool registered;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'registered': registered,
  };

  @override
  bool operator ==(Object other) =>
      other is DeviceTokenAckDto &&
      other.registered == registered &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(registered, schemaVersion);
}
