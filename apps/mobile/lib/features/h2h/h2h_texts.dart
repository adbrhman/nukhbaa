/// The words of the head-to-head league (دوري المواجهات, migration 0100).
///
/// The server decides every rule, rank and result; these only say, in
/// Arabic, what it decided. A wire value this build does not know is shown
/// as the nearest neutral word, never as an error.
library;

/// The tab's name. Only this league is called المواجهات: the fourth
/// section is المجموعة (audit M-10).
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

/// Whether [monthStart] is a month of the elite draw (NK182): November 2026
/// on. Mirrors `H2hLeaguePolicy.usesEliteDraw`; the month is the server's,
/// never the device's clock.
bool h2hUsesEliteDraw(String monthStart) {
  final DateTime? date = DateTime.tryParse(monthStart);
  return date != null &&
      (date.year > 2026 || (date.year == 2026 && date.month >= 11));
}

/// The group's number in a month of the elite draw: the four elite groups
/// (division 1) are groups 1 to 4, and the extra groups (division 2) go on
/// from 5.
int h2hGroupNumber(int division, int groupIndex) =>
    division <= 1 ? groupIndex + 1 : groupIndex + 5;

/// A group in words for [monthStart]: `المجموعة 6` from November 2026, the
/// division and the group (`الدرجة الثانية · المجموعة 1`) before it.
String h2hGroupTitle(String monthStart, int division, int groupIndex) =>
    h2hUsesEliteDraw(monthStart)
    ? 'المجموعة ${h2hGroupNumber(division, groupIndex)}'
    : '${h2hDivisionName(division)} · ${h2hGroupName(groupIndex)}';

/// What the report counts under a division key: the four elite groups and
/// the extra ones from November 2026, the division before it.
String h2hDivisionTally(String monthStart, int division, int groups) {
  if (!h2hUsesEliteDraw(monthStart)) {
    return '${h2hDivisionName(division)}: $groups';
  }
  return division <= 1
      ? 'مجموعات النخبة: $groups'
      : 'المجموعات الإضافية: $groups';
}

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

/// The four sections of a seated month, in order. The last is every match
/// of a round in the caller's group; short enough for a quarter of a phone.
const List<String> h2hSectionLabels = <String>[
  'مواجهتي',
  'الترتيب',
  'الجولات',
  'المجموعة',
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

/// Where the month stands: the round that matters now. The most a month
/// may hold is a rule, said beside it in a smaller line
/// ([h2hRoundCapLabel]).
String h2hRoundProgressLabel(int round) => 'الجولة $round';

/// The most rounds a month may hold, under the round that matters now.
const String h2hRoundCapLabel = 'من 19 كحد أقصى';

/// League points in words: `نقطة واحدة`, `نقطتان`, `3 نقاط`, `11 نقطة`.
String h2hLeaguePointsWords(int points) {
  if (points == 1) return 'نقطة واحدة';
  if (points == 2) return 'نقطتان';
  if (points >= 3 && points <= 10) return '$points نقاط';
  return '$points نقطة';
}

/// How far the caller is from the place above, in league points, as the
/// table the server sent reads: the leader is told so, a caller level on
/// points with the place above is told that, else the gap and the place.
String h2hGapLabel({required int myRank, int? aboveRank, int gap = 0}) {
  if (myRank == 1 || aboveRank == null) return 'أنت في الصدارة';
  if (gap <= 0) return 'متعادل بالنقاط مع المركز $aboveRank';
  return '${h2hLeaguePointsWords(gap)} عن المركز $aboveRank';
}

/// The zone the caller stands in if the month ended now.
const String h2hInPromotionZone = 'في منطقة الصعود';

/// The zone the caller stands in if the month ended now.
const String h2hInRelegationZone = 'في منطقة الهبوط';

/// The zone the caller stands in if the month ended now, in a month of the
/// elite draw: the first three places of an elite group play the Elite Cup.
const String h2hInCupZone = 'يتأهل للكأس';

/// The table's legend for the cup places: `يتأهل للكأس أول 3`.
String h2hCupLegend(int places) => 'يتأهل للكأس أول $places';

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

// NK216 walkover notes (owner's decision of 2026-11-07)
/// Under the caller's match against an absent opponent: what the round gave
/// the caller. [result] is the match's `result` (`win` or `draw`), null while
/// the round is live and the server shows points only.
String h2hWalkoverNote(String? result) => switch (result) {
  'win' => 'غاب خصمك وفزت بـ3 نقاط لأن معك توقّعًا صحيحًا واحدًا على الأقل.',
  'draw' => 'غاب خصمك، ولم يكن معك توقّع صحيح، فحصلت على نقطة واحدة فقط.',
  _ =>
    'غاب خصمك: تفوز بـ3 نقاط إن كان معك توقّع صحيح واحد على الأقل، '
        'وإلا تأخذ نقطة واحدة.',
};

/// Under another pair with an absent side. [winner] is the pair's `winner`.
String h2hPairWalkoverNote(String? winner) => switch (winner) {
  'home_point' || 'away_point' =>
    'غاب أحد طرفي المواجهة، ولم يكن مع الحاضر توقّع صحيح، فأخذ نقطة واحدة فقط.',
  'home' ||
  'away' => 'غاب أحد طرفي المواجهة، وحسمها الحاضر بتوقّع صحيح واحد على الأقل.',
  _ =>
    'غاب أحد طرفي المواجهة: يفوز الحاضر بتوقّع صحيح واحد على الأقل، '
        'وإلا يأخذ نقطة واحدة.',
};

/// The opponent's name while it is secret: the server names nobody until
/// the round's last match kicks off (decided 2026-10-25). Never read as the
/// group average.
const String h2hSecretOpponent = 'خصم سري';

/// When a secret opponent is named: at the round's last kickoff, on the
/// Riyadh clock, when the server sent it; else in words.
String h2hRevealLabel(String? revealsAt) {
  final String time = h2hKickoffTime(revealsAt);
  if (revealsAt == null || time == '—') {
    return 'يُكشف عند انطلاق آخر مباراة في الجولة';
  }
  return 'يُكشف الساعة $time';
}

/// Why nobody's match of a round is shown yet.
const String h2hSecretPairs =
    'مواجهات هذه الجولة سرية حتى انطلاق آخر مباراة فيها.';

/// Under a round whose opponents only the owner admin can read yet.
const String h2hOwnerOnlyPairs = 'سرّية عن اللاعبين، وتراها أنت وحدك.';

/// After a round's line in a player's month, when only the owner reads it.
const String h2hOwnerOnlyTag = 'سرّي عن اللاعبين';

/// In place of the opponent's picks while the opponent is secret.
const String h2hSecretPick = 'مخفي حتى كشف الخصم';

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
  'خصمك في كل جولة سري، ويُكشف عند انطلاق آخر مباراة فيها.',
  'من يجمع نقاط توقّع أكثر في الجولة يفوز بـ3 نقاط، والتعادل نقطة.',
  'من لم يتوقّع في الجولة يخسرها.',
  'المباراة التي تُؤجَّل، أو لا تُسجَّل نتيجتها حتى نهاية اليوم التالي '
      'للجولة، لا تُحتسب لأحد، وتُحسم الجولة بما لُعب.',
  'في نهاية الشهر يصعد أوائل كل درجة ويهبط أواخرها، حتى 3 لاعبين بحسب '
      'عدد المجموعة. لا صعود من الأولى ولا هبوط من الرابعة.',
  'لتدخل القرعة: توقّع في 5 أيام مختلفة على الأقل خلال الشهر السابق.',
];

// NK172 month-specific rules
/// Rules effective from December 2026; earlier months retain their own rules.
/// They tell the month as the server plays it (NK276, owner 2026-11-14):
/// the four groups of 80 and the extra groups, the Elite Cup in four days,
/// and the carry into the next month (NK275).
const List<String> h2hDecemberRules = <String>[
  // NK276_rules
  'المجموعات 1 إلى 4 تضم 80 لاعبًا، 20 في كل مجموعة، والباقون في مجموعات '
      'من 20 تبدأ بالمجموعة 5.',
  'في كل جولة تواجه لاعبًا واحدًا من مجموعتك، وفي الشهر 19 جولة على الأكثر.',
  'خصمك سري، ويُكشف عند انطلاق آخر مباراة في الجولة.',
  'من يجمع نقاط توقّع أكثر في الجولة يفوز بـ3 نقاط، والتعادل نقطة.',
  // NK216_13
  'إذا غاب خصمك وأنت توقّعت، تفوز بـ3 نقاط إن كان معك توقّع صحيح واحد على '
      'الأقل، وإلا تأخذ نقطة واحدة فقط. الغائب يخسر، وغيابك أنت يبقى خسارة.',
  'من لم يتوقّع في الجولة يخسرها، وإذا غاب الطرفان يخسران معًا.',
  'المباراة المؤجلة أو الخارجة من يوم الجولة، أو التي لا تُسجَّل نتيجتها '
      'حتى نهاية اليوم التالي، لا تُحتسب لأي طرف.',
  'داخل المجموعة: نقاط الدوري أولًا، ثم نقاط التوقع، ثم المواجهات '
      'بين المتعادلين، ثم الإصابات الدقيقة، ثم أسبقية المقعد.',
  'الغياب في المجموعات 1 إلى 4: بعد جولتين متتاليتين بلا أي توقّع يصلك '
      'تنبيه، وبعد الثالثة يُبدَّل مقعدك قبل الجولة التالية بأفضل بديل نشط '
      'من المجموعة 5 فما بعدها، وتبقى نقاط المقعد مع المقعد. لا هبوط '
      'بالغياب بعد الجولة 19.',
  'كأس النخبة بعد الجولة 19 في 4 أيام مباريات: في اليوم الأول نصف نهائي '
      'أصحاب المركز الأول في المجموعات 1 إلى 4 بالقرعة، وفي اليوم الثاني '
      'نهائيهم ويُتوَّج بطل كأس النخبة.',
  'في اليوم الثالث نصف نهائي أصحاب المركز الثاني فيما بينهم ونصف نهائي '
      'أصحاب المركز الثالث فيما بينهم، في اليوم نفسه وكلٌّ في كأس منفصلة. '
      'وفي اليوم الرابع النهائيان معًا، ويُتوَّج ثاني الكأس وثالثها.',
  'تُحسم مواجهة الكأس بمباريات يومها وحده: من توقّع يفوز على من لم يتوقّع، '
      'ثم الأكثر نقاط توقّع، ثم الأكثر إصابات دقيقة، ثم الأفضل في الدوري '
      'هذا الشهر، وإذا غاب الطرفان يخسران معًا.',
  'لا تُلعب الكأس في يوم فيه أقل من 6 مباريات، فتتأخر إلى يوم المباريات '
      'التالي، ولو امتدت إلى الشهر التالي. وتبدأ جولات الشهر التالي بعد '
      'آخر تتويج.',
  'في نهاية الشهر يهبط آخر 3 من كل مجموعة من 1 إلى 4 إلى المجموعة 5، '
      'ويُكمَل الثمانون بالأكثر التزامًا من المجموعتين 5 و6 معًا. ثم يُرتَّب '
      'الثمانون بترتيب الشهر: المركز في المجموعة، ثم نقاط التوقع، ثم '
      'الإصابات الدقيقة، ثم نقاط الدوري، ويُوزَّعون من جديد على المجموعات '
      'الأربع.',
  'من المجموعة 5 فما بعدها: يهبط آخر 5 من كل مجموعة إلى التي تحتها، '
      'ويصعد بدلهم أكثر 5 التزامًا من المجموعة التي تحتها.',
  'الالتزام: الأقل غيابًا (جولات بلا توقّع) أولًا، ثم الأكثر توقّعات، ثم '
      'الأكثر إصابات دقيقة، ثم الأكثر نتائج صحيحة، ثم الأكثر نقاطًا.',
  'متصدّر كل مجموعة في نهاية الشهر بطل مجموعته، ويحصل على شارة بطل '
      'المواجهات.',
  'يُحتسب تصحيح النتائج حتى إغلاق الشهر: بعد 3 ساعات من نهايته مع اكتمال '
      'النتائج، أو بعد 3 أيام على الأكثر. والنتيجة المتأخرة بعد نهاية اليوم '
      'التالي للجولة لا تُحتسب لها.',
  'لتبقى في المجموعات الشهر التالي توقّع في 5 أيام مختلفة على الأقل خلال '
      'الشهر، ومن لم يبلغها يخرج. واللاعب الجديد يدخل القرعة التالية في آخر '
      'المجموعات بالشرط نفسه.',
];

/// Rules of November 2026, the first month of the elite draw (NK182, NK183).
const List<String> h2hNovemberRules = <String>[
  'في أول الشهر يُختار 80 لاعباً: الأقل غياباً عن توقّع مباريات الشهر '
      'الماضي أولاً، ثم الأعلى نقاطاً، ثم الأكثر إصابات دقيقة. يُقسَّمون '
      'بالتساوي إلى 4 مجموعات من 20 هي المجموعات 1 إلى 4، والباقون في '
      'مجموعات إضافية من 20 تبدأ بالمجموعة 5.',
  'الجولة يوم مباريات يُعلن قبل يومه، وتواجه فيها لاعباً واحداً من '
      'مجموعتك. في الدوري 19 جولة، تلاقي فيها كل لاعب في مجموعتك مرة واحدة.',
  'خصمك في كل جولة سري، ويُكشف عند انطلاق آخر مباراة فيها.',
  'من يجمع نقاط توقّع أكثر في الجولة يفوز بـ3 نقاط، والتعادل نقطة.',
  // NK216_14
  'من لم يتوقّع في الجولة يخسرها. ومن الجولة 7: إذا غاب خصمك وأنت توقّعت '
      'تفوز بـ3 نقاط إن كان معك توقّع صحيح واحد على الأقل، وإلا تأخذ نقطة '
      'واحدة فقط، وإذا غاب الطرفان يخسران معًا.',
  'المباراة التي تُؤجَّل، أو لا تُسجَّل نتيجتها حتى نهاية اليوم التالي '
      'للجولة، لا تُحتسب لأحد، وتُحسم الجولة بما لُعب.',
  'الغياب في المجموعات 1 إلى 4: بعد جولتين متتاليتين بلا أي توقّع يصلك '
      'تنبيه، وبعد الثالثة يُبدَّل مقعدك قبل ساعة من الجولة التالية بأفضل '
      'بديل نشط من المجموعة 5 فما فوق. من الجولة 7 تبقى نقاط المقعد مع '
      'المقعد: يأخذ القادم نقاط من سبقه فيه، ويأخذ الهابط نقاط المقعد '
      'الذي ينتقل إليه؛ وقبلها يحتفظ كل لاعب بنقاطه. لا يُحتسب '
      'الغياب في يوم بلا مباريات أو عند تعطّل النظام، ولا هبوط بالغياب '
      'بعد الجولة 19.',
  'كأس النخبة بعد الجولة 19: أصحاب المركز الأول والثاني والثالث في '
      'المجموعات 1 إلى 4 يلعبون ثلاث كؤوس منفصلة، كأس للأوائل وكأس '
      'للثواني وكأس للثوالث، لكل كأس نصف نهائي بالقرعة ونهائي. لا تختلط '
      'الكؤوس، ولا هبوط بحسب المركز في هذا الشهر.',
];

/// Selects the rule set by the player's month, not by the device's current date.
bool h2hUsesDecemberRules(String monthStart) {
  final date = DateTime.tryParse(monthStart);
  return date != null &&
      (date.year > 2026 || (date.year == 2026 && date.month >= 12));
}

/// The rules displayed for [monthStart]: December 2026 on read the elite
/// month with its carry and the four-day cup (NK276), November 2026 has the
/// elite draw's rules, earlier months the ladder's.
List<String> h2hRulesForMonth(String monthStart) {
  if (h2hUsesDecemberRules(monthStart)) return h2hDecemberRules;
  if (h2hUsesEliteDraw(monthStart)) return h2hNovemberRules;
  return h2hRules;
}

// NK172_041
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

/// A kickoff (ISO-8601 UTC) as `HH:MM` on the Riyadh clock, the clock the
/// league's days are counted in; an unreadable one is a dash.
String h2hKickoffTime(String? iso) {
  final DateTime? utc = iso == null ? null : DateTime.tryParse(iso)?.toUtc();
  if (utc == null) return '—';
  final DateTime riyadh = utc.add(const Duration(hours: 3));
  return '${riyadh.hour.toString().padLeft(2, '0')}:'
      '${riyadh.minute.toString().padLeft(2, '0')}';
}

/// A fixture's state as the server sent it: `not_started`, `live`,
/// `finished` or `void`.
String h2hFixtureStateLabel(String state) => switch (state) {
  'live' => 'جارية',
  'finished' => 'انتهت',
  'void' => 'لا تُحتسب',
  _ => 'لم تبدأ',
};

/// In place of the opponent's pick of a fixture that has not kicked off.
const String h2hHiddenPick = 'مخفي حتى الانطلاق';

/// A predicted scoreline, home first.
String h2hScoreline(int home, int away) => '$home - $away';
