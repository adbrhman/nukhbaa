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

/// A picture sent in a support conversation (migration 0188): JPEG, PNG or
/// WEBP, at most [maxBytes], and the file's own signature must match the
/// type it claims, so nothing but a picture is ever stored or served.
final class SupportImage {
  const SupportImage._(this.bytes, this.mime);

  /// 512 KB, as the avatars (0033); the app shrinks a photo well under it.
  static const int maxBytes = 512 * 1024;

  /// The types a support picture may have.
  static const Set<String> mimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  /// What the inbox and a push say for a message that is only a picture.
  static const String preview = '📷 صورة';

  /// The picture.
  final List<int> bytes;

  /// Its content type.
  final String mime;

  /// Checks what a player or an admin sent.
  static Result<SupportImage> parse(List<int> bytes, String? rawMime) {
    final String mime = (rawMime ?? '').split(';').first.trim().toLowerCase();
    if (bytes.isEmpty) {
      return const Result.err(
        AppError.validation('support.image_empty', 'الصورة فارغة.'),
      );
    }
    if (bytes.length > maxBytes) {
      return const Result.err(tooLarge);
    }
    if (!mimeTypes.contains(mime) || !_signatureMatches(bytes, mime)) {
      return const Result.err(
        AppError.validation(
          'support.image_unsupported',
          'أرسل صورة بصيغة JPEG أو PNG أو WEBP.',
        ),
      );
    }
    return Result.ok(SupportImage._(List<int>.unmodifiable(bytes), mime));
  }

  /// The answer for a picture over [maxBytes].
  static const AppError tooLarge = AppError.validation(
    'support.image_too_large',
    'الصورة أكبر من 512 كيلوبايت.',
  );

  static bool _starts(List<int> bytes, List<int> prefix, [int at = 0]) {
    if (bytes.length < at + prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (bytes[at + i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _signatureMatches(List<int> bytes, String mime) => switch (mime) {
    'image/jpeg' => _starts(bytes, const <int>[0xFF, 0xD8, 0xFF]),
    'image/png' => _starts(bytes, const <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ]),
    // RIFF....WEBP
    'image/webp' =>
      _starts(bytes, const <int>[0x52, 0x49, 0x46, 0x46]) &&
          _starts(bytes, const <int>[0x57, 0x45, 0x42, 0x50], 8),
    _ => false,
  };
}
