/// The words of the Elite Cup card (NK185, migration 0190).
///
/// The server decides every pair, day and result; these only say, in
/// Arabic, what it decided. A wire value this build does not know is shown
/// as the nearest neutral word, never as an error.
library;

import 'package:contracts/contracts.dart';

import 'h2h_texts.dart';

/// The card's title.
const String h2hCupTitle = 'كأس النخبة';

/// A player's name, or a neutral word when the server has none.
String h2hCupNameOf(H2hCupPlayerDto player) =>
    player.displayName.trim().isEmpty ? 'لاعب' : player.displayName.trim();

/// The path of [place] (the place the player finished in his elite group).
String h2hCupPathName(int place) => switch (place) {
  1 => 'مسار أوائل المجموعات',
  2 => 'مسار ثواني المجموعات',
  3 => 'مسار ثوالث المجموعات',
  _ => 'مسار الكأس',
};

/// A stage by its round wire value.
String h2hCupRoundName(String round) => switch (round) {
  'semi' => 'نصف النهائي',
  'final' => 'النهائي',
  _ => 'مرحلة',
};

/// Where a stage stands, in words.
String h2hCupPhaseName(String phase) => switch (phase) {
  'scheduled' => 'مجدولة',
  'live' => 'جارية',
  'decided' => 'انتهت',
  'skipped' => 'لا تُلعب',
  _ => 'بانتظار الجدولة',
};

/// Why a pair went one way.
String h2hCupOutcomeName(String? outcome) => switch (outcome) {
  'points' => 'بفارق النقاط',
  'exact' => 'تعادل نقاط وحُسمت بالنتائج الصحيحة',
  // NK320_01
  'direction' => 'تعادل النقاط والنتائج الدقيقة وحُسمت بالاتجاه الصحيح',
  'league' => 'تعادل كامل وحُسمت بترتيب الدوري',
  'walkover' => 'لغياب الخصم',
  'both_absent' => 'غاب الطرفان',
  _ => '',
};

/// The line under a stage that has no day yet.
String h2hCupWaitingLine(H2hCupStageDto stage) =>
    'يُحدَّد اليوم بعد انتهاء المرحلة السابقة · المتوقع الجولة '
    '${stage.expectedDay}';

/// The stage the card puts first: the first one still to play, else the
/// last one.
H2hCupStageDto? h2hCupFocusStage(MyH2hCupDto cup) {
  for (final H2hCupStageDto stage in cup.stages) {
    if (stage.phase != 'decided' && stage.phase != 'skipped') return stage;
  }
  return cup.stages.isEmpty ? null : cup.stages.last;
}

// NK315_02
/// The board's empty state: no cup stands for the month yet.
const String h2hCupBoardEmpty =
    'لم يقم كأس النخبة بعد. تظهر هنا مبارياته وتوقعات الخصوم حين يبدأ.';

/// The board could not be read.
const String h2hCupBoardLoadFailed = 'تعذّر تحميل لوحة الكأس';

/// The retry button under a failed board.
const String h2hCupBoardRetry = 'إعادة المحاولة';

/// In place of a player's pick of a fixture that has not kicked off.
const String h2hCupPickHidden = 'تظهر بعد انطلاق المباراة';

/// A player other than the caller whose fixture kicked off without his pick.
const String h2hCupNoPickOther = 'لم يتوقع';

/// The caller's own side of a fixture he did not predict.
const String h2hCupNoPickMine = 'لم تتوقع';

/// A fixture that counts for neither player.
const String h2hCupBoardVoidNote =
    'لا تُحتسب: أُجّلت أو خرجت من يوم المرحلة أو تأخّرت نتيجتها.';

/// A fixture with no registered kickoff (it counts as not started).
const String h2hCupNoKickoff = 'بلا موعد';

/// A kickoff as `HH:MM` on the Riyadh clock, or a word when the fixture has
/// none, never a bare dash.
String h2hCupKickoffLabel(String? iso) {
  if (iso == null || DateTime.tryParse(iso) == null) return h2hCupNoKickoff;
  return h2hKickoffTime(iso);
}

/// What a stage without pairs says: skipped, or not drawn yet.
String h2hCupBoardStageEmpty(String phase) => phase == 'skipped'
    ? 'لا تُلعب هذه المرحلة في هذا المسار'
    : 'تُسحب المواجهات عند جدولة المرحلة';

/// How a decided pair ended, or an empty string while it is undecided.
String h2hCupBoardPairResult(H2hCupBoardPairDto pair) {
  if (!pair.decided) return '';
  final String? winner = pair.winnerUserId;
  if (winner == null) return 'انتهت بلا فائز';
  final H2hCupPlayerDto won = pair.home.userId == winner
      ? pair.home
      : pair.away;
  return 'الفائز: ${h2hCupNameOf(won)}';
}

/// A path's title line once decided.
String h2hCupBoardTitleLine(H2hCupTitleDto title) {
  final H2hCupPlayerDto? champion = title.champion;
  if (champion == null) return 'اللقب شاغر في هذا المسار';
  return champion.isMe
      ? 'أنت بطل هذا المسار'
      : 'بطل المسار: ${h2hCupNameOf(champion)}';
}

/// The extras under a revealed pick: the double, the exact hit, the points.
String h2hCupPickExtras(H2hPickDto pick) => <String>[
  if (pick.isDouble) 'مضاعفة',
  if (pick.exact) 'دقيقة',
  if (pick.points != null) '+${pick.points} ن',
].join(' · ');

/// The caller's pair in [stage], or null (a bye, a stage not drawn, or a
/// stage the caller is out of).
H2hCupPairDto? h2hCupMyPair(H2hCupStageDto stage) {
  for (final H2hCupPairDto pair in stage.pairs) {
    if (pair.isMine) return pair;
  }
  return null;
}
