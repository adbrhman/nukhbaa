/// The words of the head-to-head league (دوري المواجهات, migration 0100).
///
/// The server decides every rule, rank and result; these only say, in
/// Arabic, what it decided. A wire value this build does not know is shown
/// as the nearest neutral word, never as an error.
library;

/// The tab's name.
const String h2hTitle = 'المواجهات';

/// The league's name.
const String h2hLeagueName = 'دوري المواجهات';

/// The division [level] 1..4 in words.
String h2hDivisionName(int level) => switch (level) {
  1 => 'الدرجة الأولى',
  2 => 'الدرجة الثانية',
  3 => 'الدرجة الثالثة',
  _ => 'الدرجة الرابعة',
};

/// The 0-based group [index] of the open division, in words.
String h2hGroupName(int index) => 'المجموعة ${index + 1}';

/// A round's result for the caller: `win`, `draw` or `loss`.
String h2hResultLabel(String result) => switch (result) {
  'win' => 'فوز',
  'draw' => 'تعادل',
  'loss' => 'خسارة',
  _ => '-',
};

/// One letter of the form strip: `win`, `draw` or `loss`.
String h2hFormLetter(String result) => switch (result) {
  'win' => 'ف',
  'draw' => 'ت',
  'loss' => 'خ',
  _ => '-',
};

/// A round's phase as the server sent it: `open` (the next round, taking
/// predictions now), `upcoming` (a later one), `live`, `settled` or
/// `voided`. Version 1 servers sent `upcoming` for every round not started.
String h2hRoundStatusLabel(String status) => switch (status) {
  'open' => 'مفتوحة',
  'live' => 'جارية',
  'settled' => 'مكتملة',
  'voided' => 'ملغاة',
  _ => 'قادمة',
};

/// The three sections of a seated month, in order.
const List<String> h2hSectionLabels = <String>[
  'المواجهة',
  'الترتيب',
  'الجولات',
];

/// The Arabic month names, January first.
const List<String> _months = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// A `YYYY-MM-DD` Riyadh day as `7 نوفمبر`. The day is the server's and is
/// never shifted into the device's zone; a value that is not such a day is
/// shown as it arrived.
String h2hDayLabel(String isoDay) {
  final RegExpMatch? m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})$',
  ).firstMatch(isoDay);
  if (m == null) return isoDay;
  final int month = int.parse(m.group(2)!);
  final int day = int.parse(m.group(3)!);
  if (month < 1 || month > 12) return isoDay;
  return '$day ${_months[month - 1]}';
}

/// The month of a `YYYY-MM-DD` day as `نوفمبر 2026`.
String h2hMonthLabel(String isoDay) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-\d{2}$').firstMatch(isoDay);
  if (m == null) return isoDay;
  final int month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return isoDay;
  return '${_months[month - 1]} ${m.group(1)}';
}

/// A round's points, as the server sent them: an integer for a player, and
/// for the group average one decimal unless it is whole.
String h2hPointsLabel(num points) {
  if (points == points.roundToDouble()) return points.round().toString();
  return points.toStringAsFixed(1);
}

/// The caller's place in the group: `3 من 20`.
String h2hRankLabel(int rank, int of) => '$rank من $of';

/// Where the month stands: the round that matters now out of the most a
/// month may hold.
String h2hRoundProgressLabel(int round) => 'الجولة $round من 19 كحد أقصى';

/// The whole days left in the month after today, as the server counted
/// them (Riyadh days).
String h2hDaysLeftLabel(int days) {
  if (days <= 0) return 'آخر يوم في الشهر';
  if (days == 1) return 'باقي يوم واحد';
  if (days == 2) return 'باقي يومان';
  if (days <= 10) return 'باقي $days أيام';
  return 'باقي $days يومًا';
}

/// The time left until a kickoff, in hours and minutes: `3 س 20 د`. Under
/// a minute it says so; once the kickoff has passed, the round has started.
String h2hCountdownLabel(Duration left) {
  if (left <= Duration.zero) return 'بدأت';
  if (left < const Duration(minutes: 1)) return 'أقل من دقيقة';
  final int hours = left.inHours;
  final int minutes = left.inMinutes % 60;
  if (hours == 0) return '$minutes د';
  return '$hours س $minutes د';
}

/// The opponent's name when the caller plays the group average.
const String h2hAverageOpponent = 'متوسط المجموعة';

/// The name shown for a member with no display name.
const String h2hUnnamed = 'لاعب';

/// Under the list of rounds: when a round becomes known.
const String h2hRoundsNote = 'تُعلن الجولة قبل يوم مبارياتها.';

/// The rules, in the order the rules card and sheet list them.
const List<String> h2hRules = <String>[
  'في أول كل شهر يُقسَّم اللاعبون إلى درجات من 20 لاعبًا: الأولى ثم '
      'الثانية ثم الثالثة، والباقون في الرابعة.',
  'الجولة يوم مباريات يُعلن قبل يومه، وتواجه فيها لاعبًا واحدًا من '
      'مجموعتك. في الشهر 19 جولة على الأكثر.',
  'من يجمع نقاط توقّع أكثر في الجولة يفوز بـ3 نقاط، والتعادل نقطة.',
  'من لم يتوقّع في الجولة يخسرها.',
  'في نهاية الشهر يصعد أوائل كل درجة ويهبط أواخرها، حتى 3 لاعبين بحسب '
      'عدد المجموعة. لا صعود من الأولى ولا هبوط من الرابعة.',
  'لتدخل القرعة: توقّع في 5 أيام مختلفة على الأقل خلال الشهر السابق.',
];

/// The state of a month without a seat for the caller: a title and a line.
({String title, String body}) h2hStateMessage(String state, String startsOn) =>
    switch (state) {
      'draw_pending' => (
        title: 'القرعة لم تُجرَ بعد',
        body:
            'تُجرى قرعة الشهر بعد اعتماد نتائج الشهر الماضي. '
            'عد بعد قليل لترى مجموعتك.',
      ),
      'not_in_draw' => (
        title: 'لست في قرعة هذا الشهر',
        body:
            'يدخل القرعة من توقّع في 5 أيام على الأقل خلال الشهر السابق. '
            'توقّع هذا الشهر لتلحق بقرعة الشهر القادم.',
      ),
      _ => (
        title: 'ينطلق ${h2hDayLabel(startsOn)}',
        body:
            'مواجهة جديدة في كل جولة أمام لاعب من مجموعتك، '
            'وصعود وهبوط في نهاية كل شهر.',
      ),
    };
