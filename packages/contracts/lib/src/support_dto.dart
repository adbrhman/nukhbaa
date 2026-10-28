/// The private chat between a player and Nukhbaa support (migration 0187).
///
/// The player's side: `GET /me/support/messages`, `POST
/// /me/support/messages`, `POST /me/support/read`, `GET /me/support/unread`.
/// The admins' side: `GET /admin/support/conversations`, `GET|PATCH
/// /admin/support/conversations/{id}`, `POST
/// /admin/support/conversations/{id}/messages` and `.../read`.
library;

Map<String, Object?> _map(Object? value) =>
    ((value as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
        .cast<String, Object?>();

/// One message. [sender] is `player` or `support`; a player never learns
/// which admin answered.
final class SupportMessageDto {
  /// Creates the message.
  const SupportMessageDto({
    required this.id,
    required this.sender,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportMessageDto.fromJson(Map<String, Object?> json) =>
      SupportMessageDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        id: (json['id'] as int?) ?? 0,
        sender: (json['sender'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        createdAt: (json['created_at'] as String?) ?? '',
        readAt: json['read_at'] as String?,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Ascending with time; older pages are read before the smallest id.
  final int id;

  /// `player` or `support`.
  final String sender;

  /// The text.
  final String body;

  /// When it was sent, ISO-8601 UTC.
  final String createdAt;

  /// When the other side read it, ISO-8601 UTC; absent while unread.
  final String? readAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'sender': sender,
    'body': body,
    'created_at': createdAt,
    if (readAt != null) 'read_at': readAt,
  };
}

/// A page of a conversation, oldest first.
final class SupportThreadDto {
  /// Creates the page.
  const SupportThreadDto({
    required this.unread,
    required this.messages,
    required this.hasMore,
    this.status,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportThreadDto.fromJson(Map<String, Object?> json) =>
      SupportThreadDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        status: json['status'] as String?,
        unread: (json['unread'] as int?) ?? 0,
        hasMore: (json['has_more'] as bool?) ?? false,
        messages: [
          for (final Object? m
              in (json['messages'] as List<Object?>?) ?? const <Object?>[])
            SupportMessageDto.fromJson(_map(m)),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// `open`, `closed` or `archived`; absent before the player's first
  /// message.
  final String? status;

  /// Messages from the other side the reader has not read.
  final int unread;

  /// The page, oldest first.
  final List<SupportMessageDto> messages;

  /// Whether older messages are left.
  final bool hasMore;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    if (status != null) 'status': status,
    'unread': unread,
    'has_more': hasMore,
    'messages': [for (final SupportMessageDto m in messages) m.toJson()],
  };
}

/// Body of a new message (`POST .../messages`).
final class SupportSendDto {
  /// Creates the body.
  const SupportSendDto({
    required this.body,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportSendDto.fromJson(Map<String, Object?> json) => SupportSendDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    body: (json['body'] as String?) ?? '',
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The text, 1 to 2000 characters once trimmed.
  final String body;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'body': body,
  };
}

/// A count: the player's unread answers (`GET /me/support/unread`), or the
/// messages a read marked (`POST .../read`).
final class SupportCountDto {
  /// Creates the count.
  const SupportCountDto({
    required this.count,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportCountDto.fromJson(Map<String, Object?> json) =>
      SupportCountDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        count: (json['count'] as int?) ?? 0,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The count.
  final int count;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'count': count,
  };
}

/// One line of the admins' inbox.
final class SupportConversationDto {
  /// Creates the line.
  const SupportConversationDto({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.status,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.lastSender,
    required this.supportUnread,
    required this.playerUnread,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportConversationDto.fromJson(Map<String, Object?> json) =>
      SupportConversationDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        id: (json['id'] as String?) ?? '',
        playerId: (json['player_id'] as String?) ?? '',
        playerName: (json['player_name'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'open',
        lastMessageAt: (json['last_message_at'] as String?) ?? '',
        lastMessagePreview: (json['last_message_preview'] as String?) ?? '',
        lastSender: (json['last_sender'] as String?) ?? 'player',
        supportUnread: (json['support_unread'] as int?) ?? 0,
        playerUnread: (json['player_unread'] as int?) ?? 0,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The conversation's id.
  final String id;

  /// The player's id.
  final String playerId;

  /// The player's display name.
  final String playerName;

  /// `open`, `closed` or `archived`.
  final String status;

  /// When the last message was sent, ISO-8601 UTC.
  final String lastMessageAt;

  /// The last message, one line of at most 120 characters.
  final String lastMessagePreview;

  /// `player` or `support`: who sent the last message.
  final String lastSender;

  /// The player's messages no admin has read.
  final int supportUnread;

  /// Support's messages the player has not read.
  final int playerUnread;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'player_id': playerId,
    'player_name': playerName,
    'status': status,
    'last_message_at': lastMessageAt,
    'last_message_preview': lastMessagePreview,
    'last_sender': lastSender,
    'support_unread': supportUnread,
    'player_unread': playerUnread,
  };
}

/// The admins' inbox (`GET /admin/support/conversations`).
final class SupportInboxDto {
  /// Creates the inbox.
  const SupportInboxDto({
    required this.conversations,
    required this.unreadConversations,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportInboxDto.fromJson(Map<String, Object?> json) =>
      SupportInboxDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        unreadConversations: (json['unread_conversations'] as int?) ?? 0,
        conversations: [
          for (final Object? c
              in (json['conversations'] as List<Object?>?) ?? const <Object?>[])
            SupportConversationDto.fromJson(_map(c)),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The conversations, the most recent message first.
  final List<SupportConversationDto> conversations;

  /// Conversations with an unread player message, whatever the filter.
  final int unreadConversations;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'unread_conversations': unreadConversations,
    'conversations': [
      for (final SupportConversationDto c in conversations) c.toJson(),
    ],
  };
}

/// One conversation as an admin opens it
/// (`GET /admin/support/conversations/{id}`).
final class SupportConversationPageDto {
  /// Creates the page.
  const SupportConversationPageDto({
    required this.conversation,
    required this.thread,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportConversationPageDto.fromJson(Map<String, Object?> json) =>
      SupportConversationPageDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        conversation: SupportConversationDto.fromJson(
          _map(json['conversation']),
        ),
        thread: SupportThreadDto.fromJson(_map(json['thread'])),
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The conversation's line.
  final SupportConversationDto conversation;

  /// A page of it, oldest first.
  final SupportThreadDto thread;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'conversation': conversation.toJson(),
    'thread': thread.toJson(),
  };
}

/// Body of `PATCH /admin/support/conversations/{id}`.
final class SupportStatusDto {
  /// Creates the body.
  const SupportStatusDto({
    required this.status,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportStatusDto.fromJson(Map<String, Object?> json) =>
      SupportStatusDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        status: (json['status'] as String?) ?? '',
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// `open`, `closed` or `archived`.
  final String status;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'status': status,
  };
}
