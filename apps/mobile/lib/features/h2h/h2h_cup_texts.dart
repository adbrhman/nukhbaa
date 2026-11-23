/// The words of the Elite Cup card (NK185, migration 0190).
///
/// The server decides every pair, day and result; these only say, in
/// Arabic, what it decided. A wire value this build does not know is shown
/// as the nearest neutral word, never as an error.
library;

import 'package:contracts/contracts.dart';

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

/// The caller's pair in [stage], or null (a bye, a stage not drawn, or a
/// stage the caller is out of).
H2hCupPairDto? h2hCupMyPair(H2hCupStageDto stage) {
  for (final H2hCupPairDto pair in stage.pairs) {
    if (pair.isMine) return pair;
  }
  return null;
}
