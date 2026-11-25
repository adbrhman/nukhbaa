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

// NK323_02
/// The heading of the cup laid out by day, shown to a player who watches it.
const String h2hCupDaysHeading = 'جدول الكأس حسب الأيام';

/// A cup day (1 to 4, the match days of the cup, not the calendar's) by its
/// number.
String h2hCupDayName(int day) => switch (day) {
  1 => 'اليوم الأول',
  2 => 'اليوم الثاني',
  3 => 'اليوم الثالث',
  4 => 'اليوم الرابع',
  _ => 'اليوم $day',
};

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
  // NK322_01
  'league' => 'تعادل كامل حتى في الاتجاه الصحيح وحُسمت بنقاط الشهر',
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

// NK331_01
/// The section headings of the cup tab (script 331). A player who is in the
/// cup reads "your duel now", the fixtures of that duel, "your path" and the
/// other paths; one who only watches reads the three paths in their place.
const String h2hCupNowHeading = 'مواجهتك الآن';

/// The heading of the fixtures of the caller's duel.
const String h2hCupFixturesHeading = 'مباريات المواجهة';

/// The heading of the caller's own path, for a player who is in the cup.
const String h2hCupMyPathHeading = 'مسارك';

/// The heading of the paths the caller is not in.
const String h2hCupOtherPathsHeading = 'بقية المسارات';

/// The heading of the three paths, for a player who only watches.
const String h2hCupThreePathsHeading = 'المسارات الثلاثة';

/// The heading of the tree of rounds.
const String h2hCupTreeHeading = 'شجرة الأدوار';

/// The badge of a fixture that is being played.
const String h2hCupLiveBadge = 'مباشر الآن';

/// The badge [fixture] wears, or null when it is not being played. Only the
/// server's state decides: nothing here reads the clock.
String? h2hCupBoardLiveBadge(H2hCupBoardFixtureDto fixture) =>
    fixture.state == 'live' ? h2hCupLiveBadge : null;

/// The stage of [path] that stands now: the first one still to play, else the
/// last one, or null for a path without stages. A stage left out of the path
/// (`skipped`) is not still to play.
H2hCupBoardStageDto? h2hCupBoardFocusStage(H2hCupBoardPathDto path) {
  for (final H2hCupBoardStageDto stage in path.stages) {
    if (stage.phase != 'decided' && stage.phase != 'skipped') return stage;
  }
  return path.stages.isEmpty ? null : path.stages.last;
}

/// The path of [board] the caller is in: the one where he has a pair or the
/// bye of a stage. A player who only watches is in none, so this is null.
H2hCupBoardPathDto? h2hCupBoardMyPath(H2hCupBoardDto board) {
  for (final H2hCupBoardPathDto path in board.paths) {
    for (final H2hCupBoardStageDto stage in path.stages) {
      if (stage.bye?.isMe ?? false) return path;
      for (final H2hCupBoardPairDto pair in stage.pairs) {
        if (pair.home.isMe || pair.away.isMe) return path;
      }
    }
  }
  return null;
}

/// The duel "your duel now" shows: the caller's path, its stage and his pair.
typedef H2hCupNow = ({
  H2hCupBoardPathDto path,
  H2hCupBoardStageDto stage,
  H2hCupBoardPairDto pair,
});

/// The caller's pair in the first stage of his path that is not decided, or
/// null when he only watches, or has no pair in that stage (a bye, a stage
/// not drawn yet, or a stage he is out of), or his path is over.
H2hCupNow? h2hCupBoardNow(H2hCupBoardDto board) {
  final H2hCupBoardPathDto? path = h2hCupBoardMyPath(board);
  if (path == null) return null;
  for (final H2hCupBoardStageDto stage in path.stages) {
    if (stage.phase == 'decided' || stage.phase == 'skipped') continue;
    for (final H2hCupBoardPairDto pair in stage.pairs) {
      if (pair.home.isMe || pair.away.isMe) {
        return (path: path, stage: stage, pair: pair);
      }
    }
    return null;
  }
  return null;
}

/// The fixture of [pair] the duel stands at: the one being played, else the
/// first that has not started (the server sends them by kickoff), or null
/// when every fixture is finished or void.
H2hCupBoardFixtureDto? h2hCupBoardCurrentFixture(H2hCupBoardPairDto pair) {
  for (final H2hCupBoardFixtureDto fixture in pair.fixtures) {
    if (fixture.state == 'live') return fixture;
  }
  for (final H2hCupBoardFixtureDto fixture in pair.fixtures) {
    if (fixture.state == 'not_started') return fixture;
  }
  return null;
}

/// A path's status line: its title once decided, else the stage it stands at
/// and where that stage stands.
String h2hCupBoardPathStatus(H2hCupBoardPathDto path) {
  final H2hCupTitleDto? title = path.title;
  if (title != null) return h2hCupBoardTitleLine(title);
  final H2hCupBoardStageDto? stage = h2hCupBoardFocusStage(path);
  if (stage == null) return h2hCupPhaseName('waiting');
  return '${h2hCupRoundName(stage.round)} · ${h2hCupPhaseName(stage.phase)}';
}
