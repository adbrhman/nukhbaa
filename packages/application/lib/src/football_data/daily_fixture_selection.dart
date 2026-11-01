import 'package:application/src/football_data/league_tables.dart';
import 'package:application/src/football_data/match_details_scope.dart';
import 'package:application/src/football_data/match_strength.dart';
import 'package:application/src/football_data/ports/daily_selection_log.dart';
import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/ports/provider_sync_store.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// How the daily selection behaves (`NUKHBA_DAILY_MINIMUM`, script 190).
enum DailySelectionMode {
  /// Nothing is chosen; the leagues keep their club rules.
  off,

  /// The trial: every day is scored and its choice kept in the log, but
  /// nothing is added and the leagues keep their club rules.
  shadow,

  /// The selection adds the matches of its leagues; their club rules add
  /// nothing more.
  on;

  /// Parses the variable; anything but `off` or `on` is the trial, so a
  /// server deployed without it starts in [shadow].
  static DailySelectionMode parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'off':
        return DailySelectionMode.off;
      case 'on':
        return DailySelectionMode.on;
      default:
        return DailySelectionMode.shadow;
    }
  }
}

/// One league the selection chooses from.
final class DailySelectionLeague {
  /// Creates the league.
  const DailySelectionLeague({
    required this.leagueName,
    required this.standings,
    this.outsideTableIsLast = false,
    this.guaranteed = false,
  });

  /// Its name in `football_data.leagues`, as in the provider rules.
  final String leagueName;

  /// Where its clubs' places are read.
  final StandingsRef standings;

  /// A club missing from the table is placed below its last club (the
  /// League Cup, scored by the Premier League table).
  final bool outsideTableIsLast;

  /// On a day it plays, its best match is taken first when the day has
  /// none of its matches yet (the Roshan League, decided by the owner).
  final bool guaranteed;
}

/// The day's numbers (decided by the owner on 2026-11-01, script 190).
final class DailySelectionPolicy {
  /// Creates the policy.
  const DailySelectionPolicy({
    this.minimum = 10,
    this.target = 15,
    this.busyTarget = 20,
    this.minimumScore = 35,
    this.diversityPenalty = 8,
    this.busyLeagues = const <String>{},
    this.weights = const MatchStrengthWeights(),
    this.preferredFromHour = 15,
  });

  /// Below this the best matches are taken whatever their score, and a day
  /// still short the day before is reported to the owner.
  final int minimum;

  /// The selection fills an ordinary day up to this.
  final int target;

  /// And a busy day up to this.
  final int busyTarget;

  /// From [minimum] on, a match scoring less is not added.
  final int minimumScore;

  /// Taken off a match for each match of its league already on the day,
  /// so no league fills the day by itself.
  final int diversityPenalty;

  /// A day on which every one of these leagues plays is busy.
  final Set<String> busyLeagues;

  /// The weights of [scoreMatch].
  final MatchStrengthWeights weights;

  /// Between two equal matches, one kicking off from this Riyadh hour on
  /// comes first: the players are awake.
  final int preferredFromHour;
}

/// The Riyadh day's visible, non-test fixtures: the count the head-to-head
/// rounds use (`H2hRoundStore.dayFixtures`).
typedef DayFixturesReader =
    Future<Result<H2hDayFixtures>> Function(DateTime day);

/// What one provider call gave for one league and day: null when it failed.
final class DailyPoolFetch {
  /// Creates the entry.
  const DailyPoolFetch({
    required this.rule,
    required this.day,
    required this.matches,
  });

  /// The rule of the league asked about.
  final ProviderLeagueRule rule;

  /// The Riyadh day asked about.
  final DateTime day;

  /// Every match the provider reported, or null when the call failed.
  final List<ProviderMatch>? matches;
}

/// Adds a chosen match as an admin would: true when it was added, false
/// when a copy already on the schedule was linked to it instead.
typedef DailySelectionAdder =
    Future<Result<bool>> Function({
      required ProviderLeagueRule rule,
      required ProviderMatch match,
      required Team home,
      required Team away,
      required CompetitionSeason month,
    });

/// What one selection run did.
final class DailySelectionRun {
  /// Creates the report.
  const DailySelectionRun({required this.added, required this.notes});

  /// Matches added to the schedule.
  final int added;

  /// One line per notable event, for the server log.
  final List<String> notes;
}

/// The daily selection (decided by the owner on 2026-11-01, scripts
/// 189-190): every match of the Premier League and the Champions League is
/// on the schedule by its own rule; the matches of the other leagues are
/// chosen here, day by day, by how strong they are.
///
/// * **The day's count** is the head-to-head rounds' own: every visible,
///   non-test fixture of the Riyadh day, the admins' own included.
/// * **Scores** come from [scoreMatch]: the clubs' places in their league
///   table, the big clubs, the derbies, how close the clubs are. Each match
///   loses [DailySelectionPolicy.diversityPenalty] for every match of its
///   league already on the day. Equal scores go to the owner's order of the
///   leagues, then to a kickoff the players are awake for.
/// * **How many.** Below [DailySelectionPolicy.minimum] the best matches are
///   taken whatever their score; from there on only matches of
///   [DailySelectionPolicy.minimumScore] or more, up to
///   [DailySelectionPolicy.target], or [DailySelectionPolicy.busyTarget] on
///   a busy day. One at a time, so it stops as soon as it gets there.
/// * **The Roshan League** ([DailySelectionLeague.guaranteed]): on a day it
///   plays with none of its matches yet, its best match is taken first,
///   when it is good enough or the day is short.
/// * **Never** on a day whose first match has kicked off (its round is
///   frozen), never a match kicking off within [minimumLead], an unmapped
///   or blocked club, or a match outside every monthly contest; nothing is
///   ever removed. A day is chosen only once every league of the run was
///   read for it, so the leagues are compared on the same matches.
/// * **The alert.** In the first run of the day before a day, when that day
///   would still hold fewer than [DailySelectionPolicy.minimum] matches,
///   the owner is told once ([DailyShortfallAlert]).
/// * **Shadow** ([DailySelectionMode.shadow]): the same choice is made as if
///   the selection had chosen from the start (the matches the club rules
///   added are taken off the count and compete again), and it is only kept
///   in the log.
///
/// Never throws: a failure is a note, and the next run repeats the work.
final class DailyFixtureSelection {
  /// Creates the selection. [leagues] are in the owner's order of
  /// preference.
  DailyFixtureSelection({
    required this.mode,
    required List<DailySelectionLeague> leagues,
    required Set<String> bigClubRefs,
    required List<MatchDetailsDerby> derbies,
    required LeagueTables tables,
    required ProviderSyncStore identities,
    required DayFixturesReader dayFixtures,
    this.policy = const DailySelectionPolicy(),
    this.minimumLead = const Duration(minutes: 30),
    DailySelectionLog? log,
    DailyShortfallAlert? alert,
  }) : _leagues = leagues,
       _bigClubRefs = bigClubRefs,
       _derbies = derbies,
       _tables = tables,
       _identities = identities,
       _dayFixtures = dayFixtures,
       _log = log,
       _alert = alert,
       _priority = <String, int>{
         for (var i = 0; i < leagues.length; i++)
           leagues[i].leagueName.trim(): i,
       };

  /// Off, the trial, or on.
  final DailySelectionMode mode;

  /// The day's numbers.
  final DailySelectionPolicy policy;

  /// Matches kicking off sooner than this are not chosen.
  final Duration minimumLead;

  final List<DailySelectionLeague> _leagues;
  final Set<String> _bigClubRefs;
  final List<MatchDetailsDerby> _derbies;
  final LeagueTables _tables;
  final ProviderSyncStore _identities;
  final DayFixturesReader _dayFixtures;
  final DailySelectionLog? _log;
  final DailyShortfallAlert? _alert;
  final Map<String, int> _priority;

  /// The job name an alert is recorded under, so a day is reported once.
  static String alertJob(DateTime day) => 'daily-alert:${isoDay(day)}';

  /// Whether the selection reads the matches of [leagueName].
  bool covers(String leagueName) =>
      mode != DailySelectionMode.off &&
      _priority.containsKey(leagueName.trim());

  /// Whether the selection, not the league's club rule, adds its matches.
  bool owns(String leagueName) =>
      mode == DailySelectionMode.on && covers(leagueName);

  /// Chooses the matches of each of [riyadhDays] from [pool], the matches
  /// the run read. [expectedLeagues] are the leagues the run tried to read;
  /// a day missing one of them is not chosen. Writes only when [apply] and
  /// the mode is on; the log is kept when [apply].
  Future<DailySelectionRun> run({
    required DateTime nowUtc,
    required bool apply,
    required List<DateTime> riyadhDays,
    required Set<String> expectedLeagues,
    required List<DailyPoolFetch> pool,
    required Map<String, Team> teamById,
    required List<CompetitionSeason> months,
    required DailySelectionAdder add,
  }) async {
    final notes = <String>[];
    if (mode == DailySelectionMode.off) {
      return DailySelectionRun(added: 0, notes: notes);
    }
    final clubs = await _resolveClubs(notes);
    final tables = <String, LeagueTable?>{};
    final today = riyadhDayOf(nowUtc);
    final tomorrow = DateTime.utc(today.year, today.month, today.day + 1);
    var added = 0;
    for (final day in riyadhDays) {
      added += await _selectDay(
        day: day,
        nowUtc: nowUtc,
        apply: apply,
        isTomorrow: day == tomorrow,
        expectedLeagues: expectedLeagues,
        entries: [
          for (final fetch in pool)
            if (fetch.day == day) fetch,
        ],
        teamById: teamById,
        months: months,
        add: add,
        clubs: clubs,
        tables: tables,
        notes: notes,
      );
    }
    return DailySelectionRun(added: added, notes: notes);
  }

  Future<int> _selectDay({
    required DateTime day,
    required DateTime nowUtc,
    required bool apply,
    required bool isTomorrow,
    required Set<String> expectedLeagues,
    required List<DailyPoolFetch> entries,
    required Map<String, Team> teamById,
    required List<CompetitionSeason> months,
    required DailySelectionAdder add,
    required _Clubs clubs,
    required Map<String, LeagueTable?> tables,
    required List<String> notes,
  }) async {
    final dayKey = isoDay(day);
    final info = await _dayFixtures(day);
    if (info is Err<H2hDayFixtures>) {
      notes.add('selection $dayKey: day count failed (${info.error.code})');
      return 0;
    }
    final dayInfo = (info as Ok<H2hDayFixtures>).value;
    final first = dayInfo.firstKickoff;
    if (first != null && !first.isAfter(nowUtc)) {
      notes.add('selection $dayKey: the day has begun');
      return 0;
    }

    final missing = <String>[
      for (final league in expectedLeagues)
        if (!entries.any(
          (fetch) =>
              fetch.rule.leagueName.trim() == league && fetch.matches != null,
        ))
          league,
    ];
    if (missing.isNotEmpty) {
      notes.add(
        'selection $dayKey: not every league was read '
        '(${missing.join(', ')})',
      );
      // The run at 12:05 is the last chance the day before: a day still
      // unread by then is reported on the count it has.
      if (isTomorrow &&
          mode == DailySelectionMode.on &&
          apply &&
          nowUtc.toUtc().add(const Duration(hours: 3)).hour >= 12 &&
          dayInfo.fixtureCount < policy.minimum) {
        await _alertOnce(
          day: day,
          count: dayInfo.fixtureCount,
          firstKickoff: first,
          nowUtc: nowUtc,
          notes: notes,
        );
      }
      return 0;
    }

    // The catalog ids of every club and match the leagues reported.
    final teamIds = <String, Map<String, String>>{};
    final fixtureIds = <String, Map<String, String>>{};
    final sources = <String>{for (final fetch in entries) fetch.rule.source};
    for (final source in sources) {
      final matches = <ProviderMatch>[
        for (final fetch in entries)
          if (fetch.rule.source == source) ...?fetch.matches,
      ];
      final teams = await _identities.canonicalIds(
        source: source,
        table: 'team',
        externalIds: [
          for (final match in matches) ...[
            match.homeTeamExternalId,
            match.awayTeamExternalId,
          ],
        ],
      );
      final known = await _identities.canonicalIds(
        source: source,
        table: 'fixture',
        externalIds: [for (final match in matches) match.externalId],
      );
      if (teams is Err<Map<String, String>> ||
          known is Err<Map<String, String>>) {
        notes.add('selection $dayKey: id lookup failed for $source');
        return 0;
      }
      teamIds[source] = (teams as Ok<Map<String, String>>).value;
      fixtureIds[source] = (known as Ok<Map<String, String>>).value;
    }

    final shadow = mode != DailySelectionMode.on || !apply;
    final records = <DailySelectionCandidate>[];
    final candidates = <_Candidate>[];
    final onDay = <String, int>{};
    final playing = <String>{};
    var knownOnDay = 0;
    final earliestLead = nowUtc.add(minimumLead);

    for (final fetch in entries) {
      final rule = fetch.rule;
      final leagueName = rule.leagueName.trim();
      final priority = _priority[leagueName];
      if (priority == null) {
        continue;
      }
      final league = _leagues[priority];
      for (final match in fetch.matches ?? const <ProviderMatch>[]) {
        if (riyadhDayOf(match.kickoffAt) != day) {
          continue;
        }
        playing.add(leagueName);
        final source = rule.source;
        final knownId = fixtureIds[source]?[match.externalId];
        final homeId = teamIds[source]?[match.homeTeamExternalId];
        final awayId = teamIds[source]?[match.awayTeamExternalId];
        final home = homeId == null ? null : teamById[homeId];
        final away = awayId == null ? null : teamById[awayId];

        DailySelectionCandidate refusal(String decision) =>
            DailySelectionCandidate(
              source: source,
              externalId: match.externalId,
              leagueName: leagueName,
              homeTeam: home?.name ?? match.homeTeamName,
              awayTeam: away?.name ?? match.awayTeamName,
              kickoffAt: match.kickoffAt.toUtc(),
              score: null,
              reasons: '',
              decision: decision,
            );

        if (knownId != null) {
          if (!shadow) {
            // On the schedule already (chosen earlier, or added by hand
            // and linked): it counts, and it holds its league's place.
            onDay[leagueName] = (onDay[leagueName] ?? 0) + 1;
            records.add(refusal('على الجدول'));
            continue;
          }
          knownOnDay++;
        }
        final month = monthContaining(months, match.kickoffAt);
        final String? refused;
        if (match.status != ProviderMatchStatus.scheduled) {
          refused = 'ليست مجدولة';
        } else if (!match.kickoffAt.isAfter(earliestLead)) {
          refused = 'قريبة الانطلاق';
        } else if (home == null || away == null) {
          refused = 'نادٍ غير مربوط';
        } else if (home.blocked || away.blocked) {
          refused = 'نادٍ محظور';
        } else if (month == null) {
          refused = 'خارج مسابقات الشهر';
        } else {
          refused = null;
        }
        if (refused != null || home == null || away == null || month == null) {
          records.add(refusal(refused ?? 'غير صالحة'));
          continue;
        }

        final key = league.standings.key;
        if (!tables.containsKey(key)) {
          tables[key] = await _tables.tableOf(
            league.standings,
            nowUtc: nowUtc,
            riyadhDay: day,
            notes: notes,
          );
        }
        final table = tables[key];
        final strength = scoreMatch(
          home: table?.placeOf(
            home.id.value,
            outsideIsLast: league.outsideTableIsLast,
          ),
          away: table?.placeOf(
            away.id.value,
            outsideIsLast: league.outsideTableIsLast,
          ),
          homeIsBig: clubs.big.contains(home.id.value),
          awayIsBig: clubs.big.contains(away.id.value),
          isDerby: clubs.isDerby(home.id.value, away.id.value),
          weights: policy.weights,
        );
        candidates.add(
          _Candidate(
            rule: rule,
            league: league,
            priority: priority,
            match: match,
            home: home,
            away: away,
            month: month,
            strength: strength,
            known: knownId != null,
          ),
        );
      }
    }

    final busy =
        policy.busyLeagues.isNotEmpty &&
        policy.busyLeagues.every(playing.contains);
    final target = busy ? policy.busyTarget : policy.target;
    final base = shadow
        ? (dayInfo.fixtureCount - knownOnDay < 0
              ? 0
              : dayInfo.fixtureCount - knownOnDay)
        : dayInfo.fixtureCount;
    var count = base;
    var chosen = 0;
    var added = 0;
    var earliest = first;
    final perLeague = <String, int>{...onDay};
    final remaining = <_Candidate>[...candidates];

    Future<void> take(_Candidate candidate) async {
      remaining.remove(candidate);
      final leagueName = candidate.league.leagueName.trim();
      final penalty = policy.diversityPenalty * (perLeague[leagueName] ?? 0);
      candidate.penalty = penalty;
      if (shadow) {
        candidate.decision = candidate.known
            ? 'تُختار (موجودة الآن)'
            : 'تُختار';
        count++;
        chosen++;
        perLeague[leagueName] = (perLeague[leagueName] ?? 0) + 1;
        return;
      }
      final result = await add(
        rule: candidate.rule,
        match: candidate.match,
        home: candidate.home,
        away: candidate.away,
        month: candidate.month,
      );
      switch (result) {
        case Ok<bool>(:final value):
          candidate.decision = value ? 'أُضيفت' : 'موجودة يدوياً، رُبطت';
          if (value) {
            count++;
            added++;
            notes.add(
              'selection $dayKey: added ${candidate.home.name} - '
              '${candidate.away.name} (${candidate.strength.total})',
            );
          }
          chosen++;
          perLeague[leagueName] = (perLeague[leagueName] ?? 0) + 1;
          final kickoff = candidate.match.kickoffAt.toUtc();
          final soonest = earliest;
          if (soonest == null || kickoff.isBefore(soonest)) {
            earliest = kickoff;
          }
        case Err<bool>(:final error):
          candidate.decision = 'تعذّرت الإضافة (${error.code})';
          notes.add(
            'selection $dayKey: add failed (${error.code}) '
            '${candidate.home.name} - ${candidate.away.name}',
          );
      }
    }

    // The guaranteed league first, when the day has none of its matches.
    for (final league in _leagues) {
      if (!league.guaranteed) {
        continue;
      }
      final name = league.leagueName.trim();
      if ((perLeague[name] ?? 0) > 0) {
        continue;
      }
      final own = <_Candidate>[
        for (final candidate in remaining)
          if (candidate.league.leagueName.trim() == name) candidate,
      ]..sort((a, b) => _compare(a, b, const <String, int>{}));
      if (own.isEmpty || count >= policy.busyTarget) {
        continue;
      }
      final best = own.first;
      if (count < policy.minimum ||
          best.strength.total >= policy.minimumScore) {
        await take(best);
      }
    }

    while (count < target && remaining.isNotEmpty) {
      final open = <_Candidate>[
        for (final candidate in remaining)
          if (count < policy.minimum ||
              candidate.strength.total >= policy.minimumScore)
            candidate,
      ];
      if (open.isEmpty) {
        break;
      }
      open.sort((a, b) => _compare(a, b, perLeague));
      await take(open.first);
    }

    for (final candidate in remaining) {
      candidate.decision = count >= target
          ? 'خارج السقف'
          : candidate.strength.total < policy.minimumScore
          ? 'أضعف من الحد'
          : 'لم تُختر';
    }

    var note = '';
    if (isTomorrow && count < policy.minimum) {
      if (shadow) {
        note = 'تنبيه تجريبي: $count من ${policy.minimum}';
        notes.add('selection $dayKey: would alert ($count matches)');
      } else {
        note = await _alertOnce(
          day: day,
          count: count,
          firstKickoff: earliest,
          nowUtc: nowUtc,
          notes: notes,
        );
      }
    }

    for (final candidate in candidates) {
      records.add(
        DailySelectionCandidate(
          source: candidate.rule.source,
          externalId: candidate.match.externalId,
          leagueName: candidate.league.leagueName.trim(),
          homeTeam: candidate.home.name,
          awayTeam: candidate.away.name,
          kickoffAt: candidate.match.kickoffAt.toUtc(),
          score: candidate.strength.total,
          reasons: [
            ...candidate.strength.reasons,
            if (candidate.penalty > 0) 'تنوع: -${candidate.penalty}',
          ].join('، '),
          decision: candidate.decision,
        ),
      );
    }

    final label = shadow && mode == DailySelectionMode.on
        ? 'on, not applied'
        : mode.name;
    final busyLabel = busy ? ' busy' : '';
    notes.add(
      'selection $dayKey ($label): base=$base chosen=$chosen '
      'final=$count target=$target$busyLabel',
    );

    final log = _log;
    if (log != null && apply) {
      final kept = await log.record(
        day: DailySelectionDay(
          day: day,
          mode: mode.name,
          baseCount: base,
          target: target,
          busy: busy,
          chosen: chosen,
          finalCount: count,
          note: note,
        ),
        candidates: records,
        at: nowUtc,
      );
      if (kept is Err<void>) {
        notes.add('selection $dayKey: log not kept (${kept.error.code})');
      }
    }
    return added;
  }

  /// Tells the owner about [day] unless an earlier run already did; returns
  /// the log's note.
  Future<String> _alertOnce({
    required DateTime day,
    required int count,
    required DateTime? firstKickoff,
    required DateTime nowUtc,
    required List<String> notes,
  }) async {
    final dayKey = isoDay(day);
    final alert = _alert;
    if (alert == null) {
      return '';
    }
    final job = alertJob(day);
    final last = await _identities.lastSyncAt(job);
    if (last is Ok<DateTime?> && last.value != null) {
      return 'أُرسل التنبيه';
    }
    final sent = await alert.send(
      day: day,
      fixtureCount: count,
      minimum: policy.minimum,
      firstKickoff: firstKickoff,
    );
    if (sent is Err<void>) {
      notes.add('selection $dayKey: alert failed (${sent.error.code})');
      return 'تعذّر التنبيه (${sent.error.code})';
    }
    await _identities.markSyncAt(job, nowUtc);
    notes.add('selection $dayKey: owner alerted ($count matches)');
    return 'أُرسل التنبيه: $count من ${policy.minimum}';
  }

  /// [a] before [b] when it is the better pick, [perLeague] matches of each
  /// league being on the day already.
  int _compare(_Candidate a, _Candidate b, Map<String, int> perLeague) {
    int adjusted(_Candidate c) =>
        c.strength.total -
        policy.diversityPenalty * (perLeague[c.league.leagueName.trim()] ?? 0);
    final byScore = adjusted(b).compareTo(adjusted(a));
    if (byScore != 0) {
      return byScore;
    }
    final byLeague = a.priority.compareTo(b.priority);
    if (byLeague != 0) {
      return byLeague;
    }
    final aAwake = _awake(a.match.kickoffAt);
    final bAwake = _awake(b.match.kickoffAt);
    if (aAwake != bAwake) {
      return aAwake ? -1 : 1;
    }
    final byKickoff = a.match.kickoffAt.compareTo(b.match.kickoffAt);
    if (byKickoff != 0) {
      return byKickoff;
    }
    return a.match.externalId.compareTo(b.match.externalId);
  }

  bool _awake(DateTime kickoff) =>
      kickoff.toUtc().add(const Duration(hours: 3)).hour >=
      policy.preferredFromHour;

  /// The big clubs and the derbies as catalog team ids: a club is the same
  /// whichever provider names it (Roma in the Europa League is a
  /// Highlightly id, in Serie A a football-data.org one).
  Future<_Clubs> _resolveClubs(List<String> notes) async {
    final refs = <String>{
      ..._bigClubRefs,
      for (final derby in _derbies) ...derby.first,
      for (final derby in _derbies) ...derby.second,
    };
    final bySource = <String, List<String>>{};
    for (final ref in refs) {
      final cut = ref.indexOf(':');
      if (cut <= 0) {
        continue;
      }
      bySource
          .putIfAbsent(ref.substring(0, cut), () => <String>[])
          .add(ref.substring(cut + 1));
    }
    final catalogOf = <String, String>{};
    for (final entry in bySource.entries) {
      final ids = await _identities.canonicalIds(
        source: entry.key,
        table: 'team',
        externalIds: entry.value,
      );
      switch (ids) {
        case Ok<Map<String, String>>(:final value):
          for (final id in value.entries) {
            catalogOf['${entry.key}:${id.key}'] = id.value;
          }
        case Err<Map<String, String>>(:final error):
          notes.add('club list lookup failed for ${entry.key} (${error.code})');
      }
    }
    Set<String> catalog(Set<String> clubRefs) => <String>{
      for (final ref in clubRefs)
        if (catalogOf[ref] case final String id) id,
    };
    return _Clubs(
      big: catalog(_bigClubRefs),
      derbies: [
        for (final derby in _derbies)
          (catalog(derby.first), catalog(derby.second)),
      ],
    );
  }
}

/// The big clubs and the derbies by catalog team id.
final class _Clubs {
  const _Clubs({required this.big, required this.derbies});

  final Set<String> big;
  final List<(Set<String>, Set<String>)> derbies;

  bool isDerby(String home, String away) {
    for (final (first, second) in derbies) {
      if ((first.contains(home) && second.contains(away)) ||
          (first.contains(away) && second.contains(home))) {
        return true;
      }
    }
    return false;
  }
}

/// A match the selection may choose, with its score.
final class _Candidate {
  _Candidate({
    required this.rule,
    required this.league,
    required this.priority,
    required this.match,
    required this.home,
    required this.away,
    required this.month,
    required this.strength,
    required this.known,
  });

  final ProviderLeagueRule rule;
  final DailySelectionLeague league;
  final int priority;
  final ProviderMatch match;
  final Team home;
  final Team away;
  final CompetitionSeason month;
  final MatchStrength strength;

  /// Already on the schedule (shadow mode only: added by a club rule).
  final bool known;

  /// What the selection did with it.
  String decision = '';

  /// What the diversity rule took off when it was picked.
  int penalty = 0;
}
