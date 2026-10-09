/// Numbers with their nouns, in the agreement Arabic needs.
///
/// Arabic has no plural suffix to add. One and two take the noun alone
/// ("مرة واحدة", "مرتان"), three to ten the plural ("5 مرات"), eleven to
/// ninety-nine the singular ("20 مرة", "14 لاعبًا"), and a round hundred the
/// singular again ("100 مرة"). Written as "5 لاعب" or "9 مرة" a count reads
/// as broken Arabic. Player-facing text gets this from the ICU plurals in
/// `app_ar.arb`; the admin screens are written in Arabic directly and use
/// [arabicCount].
library;

/// The five forms of one noun after a number.
final class ArabicNoun {
  /// Creates a noun from its forms.
  const ArabicNoun({
    required this.one,
    required this.two,
    required this.few,
    required this.many,
    required this.other,
  });

  /// One, with its number word: "مرة واحدة".
  final String one;

  /// Two, the dual on its own: "مرتان".
  final String two;

  /// After 3 to 10: "مرات".
  final String few;

  /// After 11 to 99: "لاعبًا".
  final String many;

  /// After 0 and a round hundred (and 101, 102): "لاعب".
  final String other;

  /// Occurrences, as the subject of a line: "مرتان".
  static const ArabicNoun times = ArabicNoun(
    one: 'مرة واحدة',
    two: 'مرتان',
    few: 'مرات',
    many: 'مرة',
    other: 'مرة',
  );

  /// Occurrences after a verb ("عاد مرتين"): the dual in the accusative.
  static const ArabicNoun timesAfterVerb = ArabicNoun(
    one: 'مرة واحدة',
    two: 'مرتين',
    few: 'مرات',
    many: 'مرة',
    other: 'مرة',
  );

  /// Players.
  static const ArabicNoun players = ArabicNoun(
    one: 'لاعب واحد',
    two: 'لاعبان',
    few: 'لاعبين',
    many: 'لاعبًا',
    other: 'لاعب',
  );

  /// Errors.
  static const ArabicNoun errors = ArabicNoun(
    one: 'خطأ واحد',
    two: 'خطآن',
    few: 'أخطاء',
    many: 'خطأً',
    other: 'خطأ',
  );

  /// Matches.
  static const ArabicNoun matches = ArabicNoun(
    one: 'مباراة واحدة',
    two: 'مباراتان',
    few: 'مباريات',
    many: 'مباراة',
    other: 'مباراة',
  );

  /// Points.
  static const ArabicNoun points = ArabicNoun(
    one: 'نقطة واحدة',
    two: 'نقطتان',
    few: 'نقاط',
    many: 'نقطة',
    other: 'نقطة',
  );

  /// App sessions.
  static const ArabicNoun sessions = ArabicNoun(
    one: 'جلسة واحدة',
    two: 'جلستان',
    few: 'جلسات',
    many: 'جلسة',
    other: 'جلسة',
  );

  /// Users, as the subject of a line: "مستخدمان".
  static const ArabicNoun users = ArabicNoun(
    one: 'مستخدم واحد',
    two: 'مستخدمان',
    few: 'مستخدمين',
    many: 'مستخدمًا',
    other: 'مستخدم',
  );

  /// Users after a preposition ("من مستخدمَين"): the dual in the genitive.
  static const ArabicNoun usersAfterPreposition = ArabicNoun(
    one: 'مستخدم واحد',
    two: 'مستخدمَين',
    few: 'مستخدمين',
    many: 'مستخدمًا',
    other: 'مستخدم',
  );
}

/// [count] followed by the form of [noun] its number needs.
String arabicCount(int count, ArabicNoun noun) {
  if (count == 1) return noun.one;
  if (count == 2) return noun.two;
  final int rest = count % 100;
  if (rest >= 3 && rest <= 10) return '$count ${noun.few}';
  if (rest >= 11) return '$count ${noun.many}';
  return '$count ${noun.other}';
}
