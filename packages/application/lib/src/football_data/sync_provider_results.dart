import 'package:application/src/football_data/follow_provider_kickoff.dart';
import 'package:application/src/football_data/ports/football_data_provider.dart';
import 'package:application/src/football_data/ports/league_repository.dart';
import 'package:application/src/football_data/ports/live_score_corrections.dart';
import 'package:application/src/football_data/ports/provider_sync_store.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Records a final scoreline for [fixtureId] and scores it -- in production
/// the same `RecordFixtureResult` + `ScoreFixture` pair the admin endpoint
/// runs, under the server's service principal.
typedef ProviderResultRecorder =
    Future<Result<void>> Function({
      required String fixtureId,
      required int homeGoals,
      required int awayGoals,
    });

/// System use-case: record the results of the fixtures the sync added, once
/// the provider reports them finished.
///
/// Only fixtures linked to the provider and still without a result are
/// looked at, and only after [settleTime] from kickoff -- so nothing is asked
/// of the provider while no added match can have ended. Fixtures are grouped
/// by provider competition and Riyadh day, one provider call per group, at
/// most [maxCallsPerRun] per run. A postponed or cancelled match is never
/// given a result; it is left for an admin, in the report's `attention`.
/// Results the admin already entered are never touched (such fixtures are
/// not pending).
///
/// Just before a result is recorded, the provider's kickoff is compared with
/// the stored one ([FollowProviderKickoff], audit C-03): a kickoff brought
/// forward that the fixtures sync never saw (announced late) moves then, so
/// the result is scored from the real kickoff and a prediction sent after it
/// earns nothing.
///
/// A finished score is not recorded the first time a provider reports it: a
/// provider can flip a match to finished with a score it corrects a little
/// later (a goal ruled out by VAR, for one). The score is recorded only once
/// the same finished score has been seen unchanged for [confirmAfter]; a
/// changed score starts the wait again. The wait is kept in memory per
/// provider and fixture, so a server restart just starts it over.
///
/// A match still without a result [lookback] after kickoff is put to the
/// admins once, with the reason when one is known, and is still asked
/// about, every [lateInterval] at most, until [lateLookback] from kickoff;
/// its first finished score then is recorded at once, having long stood.
/// Before this a match was dropped at [lookback] and nobody was told
/// (review of 2026-10-16, after the Europa League night of 2026-10-15,
/// whose results came on time). A match the provider calls postponed or
/// cancelled is asked about again only after [parkFor], so it does not
/// spend a request every run.
///
/// An admin's correction of the running score ([LiveScoreCorrections]; a
/// goal ruled out that the provider still counts, as on 2026-10-18) decides
/// the score recorded: the provider's final figure goes through
/// [LiveScoreCorrection.applyTo], and the corrected score waits
/// [confirmAfter] like any other. A correction the provider's figures moved
/// away from after it was made (a goal reported later) is not settled: it is
/// put to the admins once per provider figure and recorded only when they
/// correct it again or the match is late.
///
/// With `apply: false` (shadow mode) nothing is written. Never throws.
final class SyncProviderResults {
  /// Creates the use-case.
  SyncProviderResults({
    required Map<String, FootballDataProvider> providers,
    required ProviderSyncStore store,
    required LeagueRepository leagueRepository,
    required List<ProviderLeagueRule> rules,
    required ProviderResultRecorder recorder,
    FollowProviderKickoff? kickoffFollower,
    LiveScoreCorrections? corrections,
    this.settleTime = const Duration(minutes: 90),
    this.confirmAfter = const Duration(minutes: 15),
    this.lookback = const Duration(hours: 6),
    this.lateLookback = const Duration(hours: 24),
    this.lateInterval = const Duration(hours: 2),
    this.parkFor = const Duration(hours: 1),
    this.maxCallsPerRun = 8,
  }) : _providers = providers,
       _store = store,
       _leagues = leagueRepository,
       _rules = rules,
       _recorder = recorder,
       _kickoffs = kickoffFollower,
       _corrections = corrections;

  final Map<String, FootballDataProvider> _providers;
  final ProviderSyncStore _store;
  final LeagueRepository _leagues;
  final List<ProviderLeagueRule> _rules;
  final ProviderResultRecorder _recorder;

  /// Moves a kickoff brought forward before the result is recorded; null in
  /// tests that do not look at it, where kickoffs are not compared.
  final FollowProviderKickoff? _kickoffs;

  /// The admins' corrections of running scores; null where none are made
  /// (tests that do not look at them).
  final LiveScoreCorrections? _corrections;

  /// The unsettled corrections already put to the admins, by
  /// `source|fixtureId|providerHome-providerAway`.
  final Set<String> _unsettled = <String>{};

  /// How long after kickoff a match is first looked up.
  final Duration settleTime;

  /// How far back pending fixtures are chased on every run; a fixture
  /// older than this is late.
  final Duration lookback;

  /// How far back late fixtures are still chased.
  final Duration lateLookback;

  /// How often, at most, a provider is asked about late fixtures alone.
  final Duration lateInterval;

  /// How long a match the provider calls postponed or cancelled rests.
  final Duration parkFor;

  /// How long the same finished score must stand, seen on two runs at least
  /// this far apart, before it is recorded. [Duration.zero] records at once.
  final Duration confirmAfter;

  /// The finished score last seen per `source|fixtureId`, and since when it
  /// has stood.
  final Map<String, _FinishedSighting> _sightings =
      <String, _FinishedSighting>{};

  /// When each `source|fixtureId` was last reported postponed or cancelled.
  final Map<String, DateTime> _parked = <String, DateTime>{};

  /// The late fixtures already put to the admins, by `source|fixtureId`.
  final Set<String> _overdue = <String>{};

  /// When each group of late fixtures alone was last asked about.
  final Map<String, DateTime> _lateCalls = <String, DateTime>{};

  /// Provider calls allowed in one run.
  final int maxCallsPerRun;

  /// Runs once at [now]; writes only when [apply]. Every provider with a
  /// rule is asked about its own pending fixtures; a fixture linked to two
  /// providers is recorded by whichever reports it finished first (it is no
  /// longer pending for the other).
  Future<Result<ProviderSyncReport>> call({
    required DateTime now,
    required bool apply,
  }) async {
    final nowUtc = now.toUtc();
    final sources = <String>{
      for (final rule in _rules)
        if (_providers.containsKey(rule.source)) rule.source,
    };

    final pendingBySource = <String, List<PendingProviderFixture>>{};
    for (final source in sources) {
      final pendingResult = await _store.fixturesAwaitingResult(
        source: source,
        kickedOffFrom: nowUtc.subtract(
          lateLookback > lookback ? lateLookback : lookback,
        ),
        kickedOffBefore: nowUtc.subtract(settleTime),
      );
      if (pendingResult is Err<List<PendingProviderFixture>>) {
        return Result.err(pendingResult.error);
      }
      final pending = (pendingResult as Ok<List<PendingProviderFixture>>).value;
      if (pending.isNotEmpty) {
        pendingBySource[source] = pending;
      }
    }
    // Forget the sightings of fixtures that are no longer waiting (recorded,
    // entered by an admin, or past the look-back).
    final waitingKeys = <String>{
      for (final entry in pendingBySource.entries)
        for (final fixture in entry.value) '${entry.key}|${fixture.fixtureId}',
    };
    _sightings.removeWhere((key, _) => !waitingKeys.contains(key));
    _parked.removeWhere((key, _) => !waitingKeys.contains(key));
    _overdue.removeWhere((key) => !waitingKeys.contains(key));
    _unsettled.removeWhere(
      (key) => !waitingKeys.any((waiting) => key.startsWith('$waiting|')),
    );

    if (pendingBySource.isEmpty) {
      _lateCalls.clear();
      return const Result.ok(
        ProviderSyncReport(
          requests: 0,
          applied: 0,
          alreadyKnown: 0,
          skipped: 0,
          notes: <String>[],
        ),
      );
    }

    final leaguesResult = await _leagues.listAll();
    if (leaguesResult is Err<List<League>>) {
      return Result.err(leaguesResult.error);
    }
    final leagueNameById = <String, String>{
      for (final league in (leaguesResult as Ok<List<League>>).value)
        league.id.value: league.name.trim(),
    };
    final ruleFor = <String, ProviderLeagueRule>{
      for (final rule in _rules) '${rule.source}|${rule.leagueName}': rule,
    };

    // Group by provider, competition and Riyadh day: one call covers them.
    // A fixture linked to a provider that does not serve its competition is
    // left to the provider that does.
    final notes = <String>[];
    final attention = <ProviderSyncAttention>[];
    final groups = <String, List<PendingProviderFixture>>{};
    final groupRule = <String, ProviderLeagueRule>{};
    final groupDay = <String, DateTime>{};
    for (final entry in pendingBySource.entries) {
      for (final fixture in entry.value) {
        final leagueName = leagueNameById[fixture.leagueId];
        final rule = leagueName == null
            ? null
            : ruleFor['${entry.key}|$leagueName'];
        if (rule == null) {
          continue;
        }
        final day = riyadhDayOf(fixture.kickoffAt);
        final key = '${rule.source}|${rule.externalLeagueId}|${isoDay(day)}';
        groups.putIfAbsent(key, () => <PendingProviderFixture>[]).add(fixture);
        groupRule[key] = rule;
        groupDay[key] = day;
      }
    }

    _lateCalls.removeWhere((key, _) => !groups.containsKey(key));

    bool isLate(PendingProviderFixture fixture) =>
        nowUtc.difference(fixture.kickoffAt.toUtc()) >= lookback;

    bool resting(String source, PendingProviderFixture fixture) {
      final at = _parked['$source|${fixture.fixtureId}'];
      return at != null && nowUtc.difference(at) < parkFor;
    }

    // Puts each late fixture of [fixtures] to the admins, once; a match the
    // provider called postponed or cancelled has its own entry already.
    void flagOverdue(
      String source,
      Iterable<PendingProviderFixture> fixtures,
      String Function(PendingProviderFixture fixture) why,
    ) {
      for (final fixture in fixtures) {
        final key = '$source|${fixture.fixtureId}';
        if (!isLate(fixture) ||
            _parked.containsKey(key) ||
            !_overdue.add(key)) {
          continue;
        }
        final game = fixture.game.isEmpty
            ? 'fixture ${fixture.fixtureId}'
            : fixture.game;
        final reason = why(fixture);
        notes.add('overdue ($reason): $game');
        attention.add(
          ProviderSyncAttention(
            code: 'provider_sync.result_overdue',
            match: game,
            message:
                '«$game»: لم تصل نتيجتها من المزوّد بعد '
                '${lookback.inHours} ساعات من انطلاقها ($reason). سيعود '
                'الخادم يسأل عنها على فترات خلال ${lateLookback.inHours} '
                'ساعة من انطلاقها؛ إن عرفت النتيجة فسجّلها بنفسك الآن.',
          ),
        );
      }
    }

    String failure(String code) => code == providerQuotaErrorCode
        ? 'نفدت حصة المزوّد اليومية'
        : 'تعذّر الجلب من المزوّد: $code';

    var requests = 0;
    var applied = 0;
    var waiting = 0;
    var skipped = 0;
    final recordedIds = <String>{};
    final exhausted = <String, String?>{};
    final calls = <String, int>{};
    for (final entry in groups.entries) {
      final rule = groupRule[entry.key]!;
      // A match the provider called postponed or cancelled rests a while.
      final due = <PendingProviderFixture>[
        for (final fixture in entry.value)
          if (!resting(rule.source, fixture)) fixture,
      ];
      if (due.isEmpty) {
        continue;
      }
      if (exhausted.containsKey(rule.source)) {
        final code = exhausted[rule.source];
        flagOverdue(
          rule.source,
          due,
          (_) => code == null ? 'نفدت طلبات هذه الجولة' : failure(code),
        );
        continue;
      }
      // Late fixtures alone are asked about every [lateInterval] at most.
      final lateOnly = due.every(isLate);
      final lastLate = _lateCalls[entry.key];
      if (lateOnly &&
          lastLate != null &&
          nowUtc.difference(lastLate) < lateInterval) {
        continue;
      }
      if ((calls[rule.source] ?? 0) >= maxCallsPerRun) {
        notes.add('call budget reached for ${rule.source}; the rest waits');
        exhausted[rule.source] = null;
        flagOverdue(rule.source, due, (_) => 'نفدت طلبات هذه الجولة');
        continue;
      }
      calls[rule.source] = (calls[rule.source] ?? 0) + 1;
      requests++;
      if (lateOnly) {
        _lateCalls[entry.key] = nowUtc;
      }
      final fetched = await _providers[rule.source]!.matchesOn(
        leagueExternalId: rule.externalLeagueId,
        riyadhDay: groupDay[entry.key]!,
      );
      if (fetched is Err<List<ProviderMatch>>) {
        final code = fetched.error.code;
        notes.add('fetch ${entry.key} failed: $code');
        if (code == providerQuotaErrorCode) {
          exhausted[rule.source] = code;
        }
        flagOverdue(rule.source, due, (_) => failure(code));
        continue;
      }
      final byId = <String, ProviderMatch>{
        for (final match in (fetched as Ok<List<ProviderMatch>>).value)
          match.externalId: match,
      };

      // Why each fixture of this group is still without a result.
      final why = <String, String>{};
      for (final fixture in due) {
        if (recordedIds.contains(fixture.fixtureId)) {
          continue;
        }
        // Whatever this run finds, the earlier sighting is taken out; only a
        // finished score puts one back (below).
        final sightingKey = '${rule.source}|${fixture.fixtureId}';
        final previous = _sightings.remove(sightingKey);
        _parked.remove(sightingKey);
        why[fixture.fixtureId] = 'لم يُعلن المزوّد انتهاءها';
        final match = byId[fixture.externalId];
        if (match == null) {
          skipped++;
          why[fixture.fixtureId] = 'المزوّد لا يُرجع هذه المباراة';
          notes.add(
            'match ${fixture.externalId} not returned for ${entry.key}',
          );
          continue;
        }
        switch (match.status) {
          case ProviderMatchStatus.postponed:
          case ProviderMatchStatus.cancelled:
            skipped++;
            _parked[sightingKey] = nowUtc;
            notes.add(
              'needs admin (${match.status.name}): ${match.homeTeamName} - '
              '${match.awayTeamName}, fixture ${fixture.fixtureId}',
            );
            // Kept in the error log by the scheduler, which tells the admins.
            final game = '${match.homeTeamName} - ${match.awayTeamName}';
            attention.add(
              match.status == ProviderMatchStatus.postponed
                  ? ProviderSyncAttention(
                      code: 'provider_sync.match_postponed',
                      match: game,
                      message:
                          '«$game»: المزوّد يقول إنها مؤجّلة، فلن تُسجَّل '
                          'نتيجتها آلياً. سجّل نتيجتها بنفسك إن لُعبت، أو '
                          'أخفِها.',
                    )
                  : ProviderSyncAttention(
                      code: 'provider_sync.match_cancelled',
                      match: game,
                      message:
                          '«$game»: المزوّد يقول إنها أُلغيت، فلن تُسجَّل '
                          'لها نتيجة. أخفِها لتخرج من الترتيب.',
                    ),
            );
            continue;
          case ProviderMatchStatus.scheduled:
          case ProviderMatchStatus.live:
          case ProviderMatchStatus.unknown:
            waiting++;
            continue;
          case ProviderMatchStatus.finished:
            break;
        }
        final providerHome = match.homeGoals;
        final providerAway = match.awayGoals;
        if (providerHome == null || providerAway == null) {
          waiting++;
          continue;
        }
        // An admin's correction of the running score (a goal ruled out that
        // the provider still counts) decides the score recorded.
        final correction = _corrections?.of(fixture.fixtureId);
        final counted = correction?.applyTo(providerHome, providerAway);
        final homeGoals = counted?.homeGoals ?? providerHome;
        final awayGoals = counted?.awayGoals ?? providerAway;
        final corrected = correction == null
            ? ''
            : ', admin correction of the provider $providerHome-$providerAway';
        final label =
            '${match.homeTeamName} $homeGoals-$awayGoals '
            '${match.awayTeamName} (fixture ${fixture.fixtureId}$corrected)';

        // The same finished score must stand for [confirmAfter] before it is
        // recorded; a different score starts the wait again. A late match's
        // score has long stood: it is recorded at once.
        final unchangedSince =
            previous != null &&
                previous.homeGoals == homeGoals &&
                previous.awayGoals == awayGoals
            ? previous.since
            : null;
        final since = unchangedSince ?? nowUtc;
        _sightings[sightingKey] = _FinishedSighting(
          homeGoals,
          awayGoals,
          since,
        );
        if (!isLate(fixture) && nowUtc.difference(since) < confirmAfter) {
          waiting++;
          if (unchangedSince == null) {
            notes.add(
              previous == null
                  ? 'finished, confirming for ${confirmAfter.inMinutes} min: '
                        '$label'
                  : 'score changed from '
                        '${previous.homeGoals}-${previous.awayGoals} before it '
                        'was confirmed: $label',
            );
          }
          continue;
        }
        // A correction the provider moved away from after it was made waits
        // for the admins, who are told once per provider figure, until the
        // match is late.
        if (correction != null &&
            counted != null &&
            !counted.settled &&
            !isLate(fixture)) {
          waiting++;
          if (_unsettled.add('$sightingKey|$providerHome-$providerAway')) {
            final game = fixture.game.isEmpty
                ? '${match.homeTeamName} - ${match.awayTeamName}'
                : fixture.game;
            notes.add('correction not settled, waiting for an admin: $label');
            attention.add(
              ProviderSyncAttention(
                code: 'provider_sync.correction_unsettled',
                match: game,
                message:
                    '«$game»: صُحّحت نتيجتها إلى '
                    '${correction.homeGoals}-${correction.awayGoals} والمزوّد '
                    'يقول الآن $providerHome-$providerAway، فلن تُسجَّل '
                    'آلياً. صحّح النتيجة المباشرة أو سجّل النتيجة بنفسك؛ '
                    'وإلا سُجّلت $homeGoals-$awayGoals بعد '
                    '${lookback.inHours} ساعات من انطلاقها.',
              ),
            );
          }
          continue;
        }
        // The last look at this match before its result is recorded: a
        // kickoff brought forward that the fixtures sync never saw moves now,
        // so the result is scored from the real kickoff (C-03).
        final kickoffs = _kickoffs;
        if (kickoffs != null &&
            match.kickoffAt
                    .toUtc()
                    .difference(fixture.kickoffAt.toUtc())
                    .abs() >=
                kickoffs.kickoffTolerance) {
          final teamIds = await _store.canonicalIds(
            source: rule.source,
            table: 'team',
            externalIds: [match.homeTeamExternalId, match.awayTeamExternalId],
          );
          if (teamIds is Err<Map<String, String>>) {
            notes.add('kickoff check failed (${teamIds.error.code}): $label');
          } else {
            final ids = (teamIds as Ok<Map<String, String>>).value;
            final followed = await kickoffs(
              fixtureId: fixture.fixtureId,
              match: match,
              homeTeamId: ids[match.homeTeamExternalId],
              awayTeamId: ids[match.awayTeamExternalId],
              nowUtc: nowUtc,
              apply: apply,
              attention: attention,
            );
            if (followed != null) {
              notes.add(followed);
            }
          }
        }
        if (!apply) {
          applied++;
          recordedIds.add(fixture.fixtureId);
          notes.add('would record: $label');
          continue;
        }
        final recorded = await _recorder(
          fixtureId: fixture.fixtureId,
          homeGoals: homeGoals,
          awayGoals: awayGoals,
        );
        if (recorded is Err<void>) {
          why[fixture.fixtureId] = 'تعذّر حفظها: ${recorded.error.code}';
          notes.add('record failed (${recorded.error.code}): $label');
          continue;
        }
        applied++;
        recordedIds.add(fixture.fixtureId);
        _sightings.remove(sightingKey);
        notes.add('recorded: $label');
      }
      flagOverdue(
        rule.source,
        due.where((fixture) => !recordedIds.contains(fixture.fixtureId)),
        (fixture) => why[fixture.fixtureId] ?? 'لم يُعلن المزوّد انتهاءها',
      );
    }

    return Result.ok(
      ProviderSyncReport(
        requests: requests,
        applied: applied,
        alreadyKnown: waiting,
        skipped: skipped,
        notes: notes,
        attention: attention,
      ),
    );
  }
}

/// A finished score a provider reported, and since when it has stood.
final class _FinishedSighting {
  const _FinishedSighting(this.homeGoals, this.awayGoals, this.since);

  final int homeGoals;
  final int awayGoals;
  final DateTime since;
}
