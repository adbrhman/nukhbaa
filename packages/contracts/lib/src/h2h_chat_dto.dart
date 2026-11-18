/// The chat of the caller's head-to-head group (migration 0216).
///
/// `GET|POST /me/h2h-league/chat`, `POST /me/h2h-league/chat/read` and
/// `POST /me/h2h-league/chat/rules`. Every route is the caller's own: the
/// server finds his group by the verified token.
library;

Map<String, Object?> _map(Object? value) =>
    ((value as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
        .cast<String, Object?>();

/// One message of the group chat.
final class H2hChatMessageDto {
  /// Creates the message.
  const H2hChatMessageDto({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    required this.mine,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hChatMessageDto.fromJson(Map<String, Object?> json) =>
      H2hChatMessageDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        id: (json['id'] as int?) ?? 0,
        senderId: (json['sender_id'] as String?) ?? '',
        senderName: (json['sender_name'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        createdAt: (json['created_at'] as String?) ?? '',
        mine: (json['mine'] as bool?) ?? false,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Ascending with time.
  final int id;

  /// The player who wrote it.
  final String senderId;

  /// The sender's display name.
  final String senderName;

  /// The text.
  final String body;

  /// When it was sent, ISO-8601 UTC.
  final String createdAt;

  /// Whether the caller wrote it.
  final bool mine;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'sender_id': senderId,
    'sender_name': senderName,
    'body': body,
    'created_at': createdAt,
    'mine': mine,
  };
}

/// What the caller sees of his group's chat: the newest messages, oldest
/// first, and where he stands in it.
final class H2hChatPageDto {
  /// Creates the page.
  const H2hChatPageDto({
    required this.hasGroup,
    required this.muted,
    required this.rulesAccepted,
    required this.unread,
    required this.messages,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hChatPageDto.fromJson(Map<String, Object?> json) => H2hChatPageDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    hasGroup: (json['has_group'] as bool?) ?? false,
    muted: (json['muted'] as bool?) ?? false,
    rulesAccepted: (json['rules_accepted'] as bool?) ?? false,
    unread: (json['unread'] as int?) ?? 0,
    messages: [
      for (final Object? m
          in (json['messages'] as List<Object?>?) ?? const <Object?>[])
        H2hChatMessageDto.fromJson(_map(m)),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Whether the caller holds a seat in a group; without one there is no
  /// chat.
  final bool hasGroup;

  /// Whether an admin barred the caller from writing.
  final bool muted;

  /// Whether the caller accepted the chat rules.
  final bool rulesAccepted;

  /// Messages of others after the last one the caller read.
  final int unread;

  /// The page, oldest first.
  final List<H2hChatMessageDto> messages;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'has_group': hasGroup,
    'muted': muted,
    'rules_accepted': rulesAccepted,
    'unread': unread,
    'messages': [for (final H2hChatMessageDto m in messages) m.toJson()],
  };
}

/// The answer to a chat command that returns nothing: it was done.
final class H2hChatAckDto {
  /// Creates the answer.
  const H2hChatAckDto({this.schemaVersion = currentSchemaVersion});

  /// Deserializes from a JSON map.
  factory H2hChatAckDto.fromJson(Map<String, Object?> json) =>
      H2hChatAckDto(schemaVersion: (json['schema_version'] as int?) ?? 1);

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'ok': true,
  };
}
