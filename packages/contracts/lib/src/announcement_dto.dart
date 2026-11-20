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
///
/// [requestId] is a UUID the app makes once per message and sends again with
/// every retry of it (audit M-14): the server publishes it as that
/// announcement, so a "send" pressed again after a timeout reaches nobody
/// twice. Omitted when null, as older apps send.
final class PublishAnnouncementRequestDto {
  /// Creates the request DTO.
  const PublishAnnouncementRequestDto({
    required this.title,
    required this.body,
    this.requestId,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory PublishAnnouncementRequestDto.fromJson(Map<String, Object?> json) {
    return PublishAnnouncementRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      title: json['title']! as String,
      body: json['body']! as String,
      requestId: json['request_id'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The short headline shown in the notification row.
  final String title;

  /// The instruction text itself.
  final String body;

  /// The id this message is published under, or null to let the server
  /// make one.
  final String? requestId;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'title': title,
    'body': body,
    'request_id': ?requestId,
  };

  @override
  bool operator ==(Object other) =>
      other is PublishAnnouncementRequestDto &&
      other.title == title &&
      other.body == body &&
      other.requestId == requestId &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(title, body, requestId, schemaVersion);
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
    this.status = published,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field, and [status] to [published] for the
  /// servers before script 290.
  factory AnnouncementPublishedDto.fromJson(Map<String, Object?> json) {
    return AnnouncementPublishedDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      recipients: json['recipients']! as int,
      status: (json['status'] as String?) ?? published,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  // NK290_05
  /// [status] when it reached every active player now.
  static const String published = 'published';

  /// [status] when it waits for its content to be reviewed (script 290).
  static const String pending = 'pending';

  /// [status] when the same request was already not approved.
  static const String rejected = 'rejected';

  /// How many users received a new notification.
  final int recipients;

  /// [published], [pending] or [rejected].
  final String status;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'recipients': recipients,
    'status': status,
  };

  @override
  bool operator ==(Object other) =>
      other is AnnouncementPublishedDto &&
      other.recipients == recipients &&
      other.status == status &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(recipients, status, schemaVersion);
}

/// One announcement an admin sent, held for an owner seat or decided
/// (script 290): in `GET /admin/announcements/mine` and
/// `GET /owner/announcements`.
final class AnnouncementRequestDto {
  /// Creates the line.
  const AnnouncementRequestDto({
    required this.id,
    required this.authorName,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.decidedAt,
    this.recipients,
  });

  /// Deserializes from a JSON map.
  factory AnnouncementRequestDto.fromJson(Map<String, Object?> json) {
    final String? decided = json['decided_at'] as String?;
    return AnnouncementRequestDto(
      id: json['id']! as String,
      authorName: json['author_name']! as String,
      title: json['title']! as String,
      body: json['body']! as String,
      status: json['status']! as String,
      createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
      decidedAt: decided == null ? null : DateTime.parse(decided).toUtc(),
      recipients: json['recipients'] as int?,
    );
  }

  /// Its id.
  final String id;

  /// The admin who wrote it.
  final String authorName;

  /// The headline.
  final String title;

  /// The text.
  final String body;

  /// `pending`, `published` or `rejected`.
  final String status;

  /// When it was sent (UTC).
  final DateTime createdAt;

  /// When it was decided (UTC); null while pending.
  final DateTime? decidedAt;

  /// How many inboxes it reached once published.
  final int? recipients;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'author_name': authorName,
    'title': title,
    'body': body,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'decided_at': decidedAt?.toUtc().toIso8601String(),
    'recipients': recipients,
  };

  @override
  bool operator ==(Object other) =>
      other is AnnouncementRequestDto &&
      other.id == id &&
      other.authorName == authorName &&
      other.title == title &&
      other.body == body &&
      other.status == status &&
      other.createdAt == createdAt &&
      other.decidedAt == decidedAt &&
      other.recipients == recipients;

  @override
  int get hashCode => Object.hash(
    id,
    authorName,
    title,
    body,
    status,
    createdAt,
    decidedAt,
    recipients,
  );
}

/// The wire shape of a list of [AnnouncementRequestDto] (script 290).
final class AnnouncementRequestsDto {
  /// Creates the DTO.
  const AnnouncementRequestsDto({
    required this.requests,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory AnnouncementRequestsDto.fromJson(Map<String, Object?> json) {
    return AnnouncementRequestsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      requests: [
        for (final line in json['requests']! as List<Object?>)
          AnnouncementRequestDto.fromJson(line! as Map<String, Object?>),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The requests, in the server's order.
  final List<AnnouncementRequestDto> requests;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'requests': [for (final line in requests) line.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! AnnouncementRequestsDto ||
        other.schemaVersion != schemaVersion ||
        other.requests.length != requests.length) {
      return false;
    }
    for (var i = 0; i < requests.length; i++) {
      if (other.requests[i] != requests[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(requests));
}
