/// The Arabic words of the group chat (migration 0216, script 282).
library;

/// The chat's title.
const String h2hChatTitle = 'دردشة المجموعة';

/// The title of the rules every player accepts before he writes.
const String h2hChatRulesTitle = 'قواعد دردشة المجموعة';

/// The rules, one line each.
const List<String> h2hChatRules = <String>[
  'الدردشة لأعضاء مجموعتك فقط، ولا يراها غيرهم.',
  'الاحترام واجب: لا إساءة ولا سخرية ولا تهديد.',
  'ممنوع المحتوى الجنسي أو العنصري أو الطائفي.',
  'ممنوع الإعلان والروابط الترويجية وتكرار الرسالة.',
  'لا تشارك بياناتك الشخصية: رقم هاتف أو عنوان.',
  'يمكنك الإبلاغ عن أي رسالة وحظر أي لاعب في مجموعتك.',
  'يحق لإدارة نُخبة إخفاء الرسائل المخالفة ومنع المخالف من الكتابة.',
];

/// The message a report of a chat message puts in the player's support
/// chat (script 225's way): who wrote it, its id and its text, and why.
String h2hChatReportMessage({
  required String displayName,
  required String senderId,
  required int messageId,
  required String body,
  required String reason,
}) =>
    'بلاغ عن رسالة في دردشة المجموعة\n'
    'الاسم: $displayName\n'
    'المعرّف: $senderId\n'
    'رقم الرسالة: $messageId\n'
    'النص: $body\n'
    'السبب: $reason';
