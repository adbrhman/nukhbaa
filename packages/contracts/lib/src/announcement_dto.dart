/// Versioned wire shapes for the admin-announcement command
/// (`POST /admin/announcements`).
///
/// An announcement is the one Notifications surface that carries free text
/// (migration 0043): the prose lives in its own `notification.announcements`
/// row and each recipient's notification merely references it, so these shapes
/// describe the ADMIN's submission and its outcome — never a per-recipient
/// payload. Pure data; this file depends on nothing (Application ADR §3).
library;

/// The request body of `POST /admin/announcements` — the headline and the
/// instruction text an admin broadcasts to every active user.
///
/// Recipients are NOT part of the request: the audience is resolved
/// server-side (Security ADR §2 — never trust a client-supplied recipient).
final class PublishAnnouncementRequestDto {
  /// Creates the request DTO.
  const PublishAnnouncementRequestDto({
    required this.title,
    required this.body,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory PublishAnnouncementRequestDto.fromJson(Map<String, Object?> json) {
    return PublishAnnouncementRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      title: json['title']! as String,
      body: json['body']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The short headline shown in the notification row.
  final String title;

  /// The instruction text itself.
  final String body;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'title': title,
    'body': body,
  };

  @override
  bool operator ==(Object other) =>
      other is PublishAnnouncementRequestDto &&
      other.title == title &&
      other.body == body &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(title, body, schemaVersion);
}

/// The response of `POST /admin/announcements` — how many inboxes gained the
/// announcement.
///
/// [recipients] counts users whose inbox gained a NEW row, so a replayed
/// publish of the same announcement reports 0 rather than double-counting.
/// Carries no points field (Axiom 5).
final class AnnouncementPublishedDto {
  /// Creates the response DTO.
  const AnnouncementPublishedDto({
    required this.recipients,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory AnnouncementPublishedDto.fromJson(Map<String, Object?> json) {
    return AnnouncementPublishedDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      recipients: json['recipients']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// How many users received a new notification.
  final int recipients;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'recipients': recipients,
  };

  @override
  bool operator ==(Object other) =>
      other is AnnouncementPublishedDto &&
      other.recipients == recipients &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(recipients, schemaVersion);
}
