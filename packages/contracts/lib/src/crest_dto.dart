/// The club crests (script 265, migration 0210): the list the app reads on
/// every start (`GET /crests`) and the owner admin's page
/// (`/admin/crests`).
library;

Map<String, Object?> _map(Object? value) =>
    ((value as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
        .cast<String, Object?>();

/// `GET /crests`: the URL of every club crest the app may show, by slug.
/// A crest absent from it is not shown, and a copy the app kept is dropped.
final class CrestManifestDto {
  /// Creates the manifest.
  const CrestManifestDto({
    required this.version,
    required this.clubsEnabled,
    required this.crests,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory CrestManifestDto.fromJson(Map<String, Object?> json) =>
      CrestManifestDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        version: (json['version'] as String?) ?? '',
        clubsEnabled: (json['clubs_enabled'] as bool?) ?? false,
        crests: <String, String>{
          for (final MapEntry<String, Object?> e in _map(
            json['crests'],
          ).entries)
            if (e.value is String) e.key: e.value! as String,
        },
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Changes whenever the list changes.
  final String version;

  /// Whether club crests show at all.
  final bool clubsEnabled;

  /// The URL of each crest, by slug.
  final Map<String, String> crests;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'version': version,
    'clubs_enabled': clubsEnabled,
    'crests': crests,
  };
}

/// One club crest on the owner's page.
final class AdminCrestDto {
  /// Creates the line.
  const AdminCrestDto({
    required this.slug,
    required this.status,
    this.url,
    this.reason,
    this.complainant,
    this.changedAt,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminCrestDto.fromJson(Map<String, Object?> json) => AdminCrestDto(
    slug: (json['slug'] as String?) ?? '',
    status: (json['status'] as String?) ?? 'active',
    url: json['url'] as String?,
    reason: json['reason'] as String?,
    complainant: json['complainant'] as String?,
    changedAt: json['changed_at'] as String?,
  );

  /// The app's name for it.
  final String slug;

  /// `active`, `hidden` or `deleted`.
  final String status;

  /// Its file's URL; absent once deleted.
  final String? url;

  /// Why it was last changed.
  final String? reason;

  /// Who complained, when someone did.
  final String? complainant;

  /// When it was last changed, ISO-8601 UTC.
  final String? changedAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'slug': slug,
    'status': status,
    if (url != null) 'url': url,
    if (reason != null) 'reason': reason,
    if (complainant != null) 'complainant': complainant,
    if (changedAt != null) 'changed_at': changedAt,
  };
}

/// One change in the owner's log.
final class CrestEventDto {
  /// Creates the line.
  const CrestEventDto({
    required this.action,
    required this.reason,
    required this.at,
    this.slug,
    this.complainant,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory CrestEventDto.fromJson(Map<String, Object?> json) => CrestEventDto(
    action: (json['action'] as String?) ?? '',
    reason: (json['reason'] as String?) ?? '',
    at: (json['at'] as String?) ?? '',
    slug: json['slug'] as String?,
    complainant: json['complainant'] as String?,
  );

  /// `hidden`, `shown`, `deleted`, `clubs_on` or `clubs_off`.
  final String action;

  /// Why.
  final String reason;

  /// When, ISO-8601 UTC.
  final String at;

  /// The crest; absent for the switch.
  final String? slug;

  /// Who complained, when someone did.
  final String? complainant;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'action': action,
    'reason': reason,
    'at': at,
    if (slug != null) 'slug': slug,
    if (complainant != null) 'complainant': complainant,
  };
}

/// `GET /admin/crests`: every club crest, the switch and the latest changes.
final class AdminCrestsDto {
  /// Creates the page.
  const AdminCrestsDto({
    required this.clubsEnabled,
    required this.crests,
    required this.events,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminCrestsDto.fromJson(Map<String, Object?> json) => AdminCrestsDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    clubsEnabled: (json['clubs_enabled'] as bool?) ?? false,
    crests: <AdminCrestDto>[
      for (final Object? c
          in (json['crests'] as List<Object?>?) ?? const <Object?>[])
        AdminCrestDto.fromJson(_map(c)),
    ],
    events: <CrestEventDto>[
      for (final Object? e
          in (json['events'] as List<Object?>?) ?? const <Object?>[])
        CrestEventDto.fromJson(_map(e)),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Whether club crests show at all.
  final bool clubsEnabled;

  /// Every club crest, by slug.
  final List<AdminCrestDto> crests;

  /// The latest changes, newest first.
  final List<CrestEventDto> events;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'clubs_enabled': clubsEnabled,
    'crests': [for (final AdminCrestDto c in crests) c.toJson()],
    'events': [for (final CrestEventDto e in events) e.toJson()],
  };
}
