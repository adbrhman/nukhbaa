import 'package:contracts/src/admin_dto.dart';

/// One phone in `GET /admin/shared-devices` (script 200): every account
/// seen on it, oldest first, and when it was last seen.
final class SharedDeviceDto {
  /// Creates a phone.
  const SharedDeviceDto({required this.users, required this.lastSeen});

  /// Deserializes from a JSON map.
  factory SharedDeviceDto.fromJson(Map<String, Object?> json) {
    return SharedDeviceDto(
      users: [
        for (final user in json['users']! as List<Object?>)
          UserSummaryDto.fromJson(user! as Map<String, Object?>),
      ],
      lastSeen: DateTime.parse(json['last_seen']! as String).toUtc(),
    );
  }

  /// Every account seen on the phone.
  final List<UserSummaryDto> users;

  /// The latest sighting of any of them on it (UTC).
  final DateTime lastSeen;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'users': [for (final user in users) user.toJson()],
    'last_seen': lastSeen.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    if (other is! SharedDeviceDto ||
        other.lastSeen != lastSeen ||
        other.users.length != users.length) {
      return false;
    }
    for (var i = 0; i < users.length; i++) {
      if (other.users[i] != users[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(lastSeen, Object.hashAll(users));
}

/// The wire shape of `GET /admin/shared-devices`: every phone more than one
/// account was seen on, the most crowded first. An empty [devices] list
/// means every phone holds one account.
final class SharedDevicesDto {
  /// Creates the shared-devices DTO.
  const SharedDevicesDto({
    required this.devices,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory SharedDevicesDto.fromJson(Map<String, Object?> json) {
    return SharedDevicesDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      devices: [
        for (final device in json['devices']! as List<Object?>)
          SharedDeviceDto.fromJson(device! as Map<String, Object?>),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// One entry per shared phone.
  final List<SharedDeviceDto> devices;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'devices': [for (final device in devices) device.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! SharedDevicesDto ||
        other.schemaVersion != schemaVersion ||
        other.devices.length != devices.length) {
      return false;
    }
    for (var i = 0; i < devices.length; i++) {
      if (other.devices[i] != devices[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(devices));
}
