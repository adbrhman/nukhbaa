import 'package:shared/shared.dart';

/// Which side of a support conversation sent a message (migration 0187):
/// the player, or Nukhbaa support (an admin, always shown to the player as
/// "دعم نُخبة"). Stored with each message, so a player who later becomes an
/// admin does not turn his old messages into answers.
enum SupportSenderRole {
  /// The player who owns the conversation.
  player,

  /// Nukhbaa support: any admin.
  support;

  /// The stable wire/storage token.
  String get wireValue => name;

  /// Parses an untrusted [raw] token; an unknown one is a validation error.
  static Result<SupportSenderRole> tryParse(String? raw) {
    for (final SupportSenderRole value in SupportSenderRole.values) {
      if (value.wireValue == raw) return Result.ok(value);
    }
    return Result.err(
      AppError.validation(
        'support.sender_role_unknown',
        'Unknown support sender role: ${raw ?? '<null>'}',
      ),
    );
  }
}

/// Where a support conversation stands (migration 0187). A player who
/// writes again reopens a closed or archived conversation.
enum SupportConversationStatus {
  /// Waiting on support, or still going.
  open,

  /// Answered; support closed it.
  closed,

  /// Put away by support.
  archived;

  /// The stable wire/storage token.
  String get wireValue => name;

  /// Parses an untrusted [raw] token; an unknown one is a validation error.
  static Result<SupportConversationStatus> tryParse(String? raw) {
    for (final SupportConversationStatus value
        in SupportConversationStatus.values) {
      if (value.wireValue == raw) return Result.ok(value);
    }
    return const Result.err(
      AppError.validation(
        'support.status_unknown',
        'الحالة غير معروفة: مفتوحة أو مغلقة أو مؤرشفة.',
      ),
    );
  }
}

/// The id of a support conversation: a UUID (migration 0187).
final class SupportConversationId extends EntityId {
  /// Creates the id from its canonical UUID string.
  const SupportConversationId(super.value);

  /// Parses an untrusted [raw] id. A malformed one reads as a conversation
  /// that does not exist, so the database never sees it.
  static Result<SupportConversationId> tryParse(String? raw) {
    if (raw == null || !_uuid.hasMatch(raw)) {
      return const Result.err(notFound);
    }
    return Result.ok(SupportConversationId(raw.toLowerCase()));
  }

  /// The answer for a conversation that does not exist.
  static const AppError notFound = AppError.invariant(
    'support.conversation_not_found',
    'المحادثة غير موجودة.',
  );

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}

/// The text of one support message (migration 0187): trimmed, 1 to
/// [maxLength] characters. Typing nothing, or more than a long complaint
/// needs, is refused with an Arabic line the app shows as it is.
final class SupportMessageBody {
  const SupportMessageBody._(this.value);

  /// The longest message, in UTF-16 code units (Postgres counts characters,
  /// which are never more).
  static const int maxLength = 2000;

  /// The longest preview kept on the conversation.
  static const int previewLength = 120;

  /// The trimmed text.
  final String value;

  /// Parses what the player or the admin typed.
  static Result<SupportMessageBody> parse(String? raw) {
    final String text = (raw ?? '').trim();
    if (text.isEmpty) {
      return const Result.err(
        AppError.validation('support.empty_message', 'اكتب رسالتك أولًا.'),
      );
    }
    if (text.length > maxLength) {
      return const Result.err(
        AppError.validation(
          'support.message_too_long',
          'الرسالة أطول من 2000 حرف. قسّمها على رسالتين.',
        ),
      );
    }
    return Result.ok(SupportMessageBody._(text));
  }

  /// One line of at most [previewLength] characters for the inbox: runs of
  /// whitespace (new lines included) fold into one space.
  String get preview {
    final String line = value.replaceAll(RegExp(r'\s+'), ' ');
    if (line.length <= previewLength) return line;
    // Never cut a surrogate pair in two.
    int end = previewLength;
    final int unit = line.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end -= 1;
    return line.substring(0, end);
  }
}
