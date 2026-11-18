/// The chat of a head-to-head group (migration 0216, script 281).
///
/// Every group of the month has a chat that only its members write in; the
/// next month's group gets its own. This file holds the two pieces of it
/// that is a pure rule: what a message may say.
library;

import 'package:shared/shared.dart';

/// The text of one group-chat message: trimmed, 1 to [maxLength]
/// characters. Typing nothing, or more than a chat message needs, is
/// refused with an Arabic line the app shows as it is.
final class H2hChatBody {
  const H2hChatBody._(this.value);

  /// The longest message, in UTF-16 code units (Postgres counts characters,
  /// which are never more).
  static const int maxLength = 500;

  /// The trimmed text.
  final String value;

  /// Parses what the player typed.
  static Result<H2hChatBody> parse(String? raw) {
    final String text = (raw ?? '').trim();
    if (text.isEmpty) {
      return const Result.err(
        AppError.validation('h2h.chat_empty_message', 'اكتب رسالتك أولًا.'),
      );
    }
    if (text.length > maxLength) {
      return const Result.err(
        AppError.validation(
          'h2h.chat_message_too_long',
          'الرسالة أطول من 500 حرف. قسّمها على رسالتين.',
        ),
      );
    }
    return Result.ok(H2hChatBody._(text));
  }
}
