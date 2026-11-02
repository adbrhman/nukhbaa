/// The month crowns itself (script 204, migration 0199, decided by the owner
/// on 2026-11-02).
library;

import 'package:application/src/leaderboard/admin_crown_month_champions.dart';
import 'package:application/src/leaderboard/month_final_board.dart';
import 'package:application/src/leaderboard/month_podium.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:application/src/leaderboard/ports/month_crown_store.dart';
import 'package:application/src/leaderboard/ports/month_podium_repository.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:application/src/scoring/rescore_unscored_results.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What one run did with one month.
enum AutoCrownStep {
  /// A match may still be played, or a result was written moments ago.
  waiting,

  /// Results whose points were not all in were scored again; the crowning
  /// comes on a later run.
  rescored,

  /// Nobody is on the final board.
  empty,

  /// Two players or more are level for the crown: the owner decides.
  tie,

  /// Crowned now, the podium set and the owner told.
  crowned,

  /// Already crowned; nothing changed since.
  settled,

  /// Already crowned, and a later result changed the first three.
  changed,
}

/// One month's line of a run, for the server log.
final class AutoCrownOutcome {
  /// Creates the line.
  const AutoCrownOutcome({required this.label, required this.step, this.note});

  /// The month (`11/2026`).
  final String label;

  /// What was done.
  final AutoCrownStep step;

  /// A few words more (what it waits for, how many were rescored).
  final String? note;

  @override
  String toString() =>
      note == null ? '$label ${step.name}' : '$label ${step.name} ($note)';
}

/// Crowns each monthly contest by itself, once its last match is over:
///
/// 1. it looks at the months that ended within [window];
/// 2. a month waits while a match of it may still be played or have its
///    result coming ([MonthCrownState.waiting]); a match without a result
///    [postponedAfter] after its kickoff, or moved past the month, counts
///    as postponed and is left out, as if it never was;
/// 3. it waits [settle] after the latest result write of the month;
/// 4. it scores again, and posts, every result whose points are not all in,
///    and crowns on a later run, once nothing is left; a result still not
///    right after [maxRescores] tries is reported (`champion.rescore_stuck`,
///    the error log) and the crowning waits for an admin;
/// 5. two players or more level for the crown (points, exact scorelines,
///    right outcomes: `MonthFinalBoard.levelForCrown`) are not decided by
///    their join times: the owner is told, once, and crowns by hand;
/// 6. otherwise the first is crowned with the month's prize
///    (`MonthCrownStore.prizeFor`), as the owner, through the admin's own
///    [AdminCrownMonthChampions], and the podium is set through
///    [AdminSetMonthPodium];
/// 7. once crowned, the podium is set if it is not yet (a month the owner
///    crowned by hand after a tie gets it too), the owner is told once, and
///    a result written later that changes the first three is told once per
///    new order -- the crowning itself is never changed by the server.
///
/// Admins play and are crowned like everyone else (decided 2026-11-02).
///
/// One month failing does not stop the others; the first failure is
/// returned after the rest were tried. Never throws.
final class AutoCrownMonths {
  /// Creates the use-case over its collaborators.
  AutoCrownMonths({
    required MonthCrownStore store,
    required MonthChampionRepository champions,
    required MonthFinalBoard board,
    required AdminCrownMonthChampions crown,
    required AdminSetMonthPodium setPodium,
    required FixtureRescorer rescore,
    required OwnerNotices owner,
  }) : _store = store,
       _champions = champions,
       _board = board,
       _crown = crown,
       _setPodium = setPodium,
       _rescore = rescore,
       _owner = owner;

  final MonthCrownStore _store;
  final MonthChampionRepository _champions;
  final MonthFinalBoard _board;
  final AdminCrownMonthChampions _crown;
  final AdminSetMonthPodium _setPodium;
  final FixtureRescorer _rescore;
  final OwnerNotices _owner;

  /// The latest result write already compared with each crowned month's
  /// first three, so an unchanged month is not read again every run.
  final Map<String, DateTime> _compared = <String, DateTime>{};

  /// How many times each fixture was scored again for a crowning, so one
  /// that never comes out right stops being retried and is reported.
  final Map<String, int> _rescoredTimes = <String, int>{};

  /// How many times a fixture is scored again before it is reported stuck.
  static const int maxRescores = 3;

  /// How long after its end a month is looked at.
  static const Duration window = Duration(days: 3);

  /// How long after the latest result write the crowning waits.
  static const Duration settle = Duration(minutes: 5);

  /// How long after its kickoff a match without a result counts as
  /// postponed.
  static const Duration postponedAfter = Duration(hours: 6);

  /// The places shown in the owner's messages: the champion and the podium.
  static const int topPlaces = 3;

  /// Runs once, as of [now].
  Future<Result<List<AutoCrownOutcome>>> call({required DateTime now}) async {
    final nowUtc = now.toUtc();
    final due = await _store.dueMonths(now: nowUtc, window: window);
    if (due is Err<List<CrownDueMonth>>) {
      return Result.err(due.error);
    }

    final out = <AutoCrownOutcome>[];
    AppError? firstFailure;
    for (final month in (due as Ok<List<CrownDueMonth>>).value) {
      final DateTime? crownedAt = month.crownedAt;
      final Result<AutoCrownOutcome> step = crownedAt == null
          ? await _crownIfReady(month, nowUtc)
          : await _afterCrowning(month, crownedAt, nowUtc);
      switch (step) {
        case Ok<AutoCrownOutcome>(:final value):
          out.add(value);
        case Err<AutoCrownOutcome>(:final error):
          firstFailure ??= error;
      }
    }

    final failure = firstFailure;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(List<AutoCrownOutcome>.unmodifiable(out));
  }

  Future<Result<AutoCrownOutcome>> _crownIfReady(
    CrownDueMonth month,
    DateTime now,
  ) async {
    final stateResult = await _store.stateOf(
      season: month.seasonId,
      now: now,
      postponedAfter: postponedAfter,
    );
    if (stateResult is Err<MonthCrownState>) {
      return Result.err(stateResult.error);
    }
    final state = (stateResult as Ok<MonthCrownState>).value;
    if (state.waiting > 0) {
      return Result.ok(
        AutoCrownOutcome(
          label: month.label,
          step: AutoCrownStep.waiting,
          note: state.waitingNames,
        ),
      );
    }
    final DateTime? lastResultAt = state.lastResultAt;
    if (lastResultAt != null && now.difference(lastResultAt) < settle) {
      return Result.ok(
        AutoCrownOutcome(
          label: month.label,
          step: AutoCrownStep.waiting,
          note: 'last result ${lastResultAt.toIso8601String()}',
        ),
      );
    }

    if (state.rescore > 0) {
      final idsResult = await _store.toRescore(month.seasonId);
      if (idsResult is Err<List<FixtureRef>>) {
        return Result.err(idsResult.error);
      }
      final ids = (idsResult as Ok<List<FixtureRef>>).value;
      final stuck = <String>[
        for (final fixture in ids)
          if ((_rescoredTimes[fixture.value] ?? 0) >= maxRescores)
            fixture.value,
      ];
      if (stuck.isNotEmpty) {
        // Scored again and posted [maxRescores] times and still not right:
        // the crowning waits, and the failure goes to the error log.
        return Result.err(
          AppError.invariant(
            'champion.rescore_stuck',
            'Month ${month.label}: points still not all in after '
                '$maxRescores rescores: ${stuck.join(', ')}',
          ),
        );
      }
      AppError? failure;
      for (final fixture in ids) {
        _rescoredTimes[fixture.value] =
            (_rescoredTimes[fixture.value] ?? 0) + 1;
        final rescored = await _rescore(fixtureId: fixture.value);
        if (rescored is Err<void>) {
          failure ??= rescored.error;
        }
      }
      if (failure != null) {
        return Result.err(failure);
      }
      return Result.ok(
        AutoCrownOutcome(
          label: month.label,
          step: AutoCrownStep.rescored,
          note: '${ids.length}',
        ),
      );
    }

    final principalResult = await _ownerPrincipal();
    if (principalResult is Err<AuthenticatedUser>) {
      return Result.err(principalResult.error);
    }
    final principal = (principalResult as Ok<AuthenticatedUser>).value;

    final monthResult = await _champions.month(month.seasonId);
    if (monthResult is Err<ChampionMonth?>) {
      return Result.err(monthResult.error);
    }
    final championMonth = (monthResult as Ok<ChampionMonth?>).value;
    if (championMonth == null) {
      return const Result.err(
        AppError.invariant('champion.month_not_found', 'الشهر غير موجود'),
      );
    }

    final boardResult = await _board.top(championMonth, limit: topPlaces);
    if (boardResult is Err<List<ChampionCandidate>>) {
      return Result.err(boardResult.error);
    }
    final lines = (boardResult as Ok<List<ChampionCandidate>>).value;
    if (lines.isEmpty) {
      final told = await _tellOnce(
        month,
        kind: 'empty',
        signature: 'empty',
        title: 'شهر ${month.label} بلا لاعبين',
        body:
            'انتهى شهر ${month.label} ولا أحد في ترتيبه النهائي، '
            'فلم يُتوَّج.',
      );
      if (told is Err<void>) {
        return Result.err(told.error);
      }
      return Result.ok(
        AutoCrownOutcome(label: month.label, step: AutoCrownStep.empty),
      );
    }

    final leaders = <ChampionCandidate>[
      for (final line in lines)
        if (MonthFinalBoard.levelForCrown(line.entry, lines.first.entry)) line,
    ];
    if (leaders.length > 1) {
      final ids = <String>[for (final line in leaders) line.userId.value]
        ..sort();
      final first = leaders.first.entry;
      final told = await _tellOnce(
        month,
        kind: 'tie',
        signature: ids.join(','),
        title: 'شهر ${month.label} ينتظر قرارك: تعادل على الصدارة',
        body:
            'تساوى على المركز الأول في النقاط والنتائج الدقيقة والاتجاه '
            'الصحيح: ${_names(leaders)} '
            '(${first.totalPoints} نقطة، ${first.exactCount} نتيجة دقيقة، '
            '${first.outcomeCount} اتجاهًا صحيحًا). لم يُتوَّج الشهر '
            'تلقائيًا: توِّج بطلًا أو بطلين من لوحة المشرف ← تتويج الشهر، '
            'وتُثبَّت المنصة بعده تلقائيًا.',
      );
      if (told is Err<void>) {
        return Result.err(told.error);
      }
      return Result.ok(
        AutoCrownOutcome(
          label: month.label,
          step: AutoCrownStep.tie,
          note: ids.join(','),
        ),
      );
    }

    final prizeResult = await _store.prizeFor(month.seasonId);
    if (prizeResult is Err<String?>) {
      return Result.err(prizeResult.error);
    }
    final crowned = await _crown(
      principal: principal,
      seasonId: month.seasonId.value,
      userIds: <String>[lines.first.userId.value],
      // A match left without a result is postponed by now (step 2): it
      // does not count, so it does not hold the crown back.
      force: true,
      prize: (prizeResult as Ok<String?>).value,
    );
    if (crowned is Err<List<MonthChampion>>) {
      return Result.err(crowned.error);
    }

    final after = await _afterCrowning(month, now, now, state: state);
    if (after is Err<AutoCrownOutcome>) {
      return after;
    }
    return Result.ok(
      AutoCrownOutcome(label: month.label, step: AutoCrownStep.crowned),
    );
  }

  Future<Result<AutoCrownOutcome>> _afterCrowning(
    CrownDueMonth month,
    DateTime crownedAt,
    DateTime now, {
    MonthCrownState? state,
  }) async {
    final principalResult = await _ownerPrincipal();
    if (principalResult is Err<AuthenticatedUser>) {
      return Result.err(principalResult.error);
    }
    final principal = (principalResult as Ok<AuthenticatedUser>).value;

    // Answers the podium already set, or sets it from the final board.
    final podiumResult = await _setPodium(
      principal: principal,
      seasonId: month.seasonId.value,
    );
    if (podiumResult is Err<List<MonthPodiumPlace>>) {
      return Result.err(podiumResult.error);
    }
    final podium = (podiumResult as Ok<List<MonthPodiumPlace>>).value;

    final noted = await _store.noteOnce(
      season: month.seasonId,
      kind: 'crowned',
      signature: 'crowned',
    );
    if (noted is Err<bool>) {
      return Result.err(noted.error);
    }
    if ((noted as Ok<bool>).value) {
      final told = await _tellCrowned(month, podium, now, state);
      if (told is Err<void>) {
        return Result.err(told.error);
      }
    }

    return _compareAfterCrowning(month, crownedAt, podium);
  }

  Future<Result<void>> _tellCrowned(
    CrownDueMonth month,
    List<MonthPodiumPlace> podium,
    DateTime now,
    MonthCrownState? known,
  ) async {
    final listed = await _champions.list(limit: 50);
    if (listed is Err<List<MonthChampion>>) {
      return Result.err(listed.error);
    }
    final champions = <MonthChampion>[
      for (final champion in (listed as Ok<List<MonthChampion>>).value)
        if (champion.seasonId == month.seasonId) champion,
    ];

    final Result<MonthCrownState> read = known != null
        ? Result.ok(known)
        : await _store.stateOf(
            season: month.seasonId,
            now: now,
            postponedAfter: postponedAfter,
          );
    if (read is Err<MonthCrownState>) {
      return Result.err(read.error);
    }
    final state = (read as Ok<MonthCrownState>).value;

    final lines = <String>[
      for (final champion in champions)
        'البطل: ${champion.displayName} بـ${champion.points} نقطة '
            '(${champion.exactCount} نتيجة دقيقة)'
            '${champion.prize == null ? '، بلا نص جائزة' : '، الجائزة: ${champion.prize}'}.',
      for (final place in podium)
        '${place.place == 2 ? 'الثاني' : 'الثالث'}: ${place.displayName} '
            'بـ${place.points} نقطة (${place.exactCount} نتيجة دقيقة).',
      if (state.skipped > 0)
        'مباريات لم تُحسب لأنها بلا نتيجة (مؤجلة أو ملغاة): '
            '${state.skippedNames ?? state.skipped}.',
      'تمّ بعد آخر نتيجة في الشهر وبعد احتساب كل النقاط. أضف صور '
          'المتوَّجين من لوحة المشرف ← تتويج الشهر.',
    ];
    return _owner.tell(
      title: 'تُوِّج شهر ${month.label}',
      body: lines.join('\n'),
    );
  }

  Future<Result<AutoCrownOutcome>> _compareAfterCrowning(
    CrownDueMonth month,
    DateTime crownedAt,
    List<MonthPodiumPlace> podium,
  ) async {
    final writtenResult = await _store.resultsWrittenAfter(
      season: month.seasonId,
      since: crownedAt,
    );
    if (writtenResult is Err<DateTime?>) {
      return Result.err(writtenResult.error);
    }
    final DateTime? written = (writtenResult as Ok<DateTime?>).value;
    final settled = AutoCrownOutcome(
      label: month.label,
      step: AutoCrownStep.settled,
    );
    if (written == null || _compared[month.seasonId.value] == written) {
      return Result.ok(settled);
    }

    final monthResult = await _champions.month(month.seasonId);
    if (monthResult is Err<ChampionMonth?>) {
      return Result.err(monthResult.error);
    }
    final championMonth = (monthResult as Ok<ChampionMonth?>).value;
    if (championMonth == null) {
      return Result.ok(settled);
    }
    final crowned = championMonth.crowned;
    final boardResult = await _board.top(
      championMonth,
      limit: crowned.length + podium.length,
    );
    if (boardResult is Err<List<ChampionCandidate>>) {
      return Result.err(boardResult.error);
    }
    final lines = (boardResult as Ok<List<ChampionCandidate>>).value;
    _compared[month.seasonId.value] = written;

    final firstNow = <String>{
      for (final line in lines.take(crowned.length)) line.userId.value,
    };
    final firstThen = <String>{for (final id in crowned) id.value};
    final nextNow = <String>[
      for (final line in lines.skip(crowned.length).take(podium.length))
        line.userId.value,
    ];
    final nextThen = <String>[for (final place in podium) place.userId.value];
    final bool same =
        lines.length >= crowned.length &&
        firstNow.length == firstThen.length &&
        firstNow.containsAll(firstThen) &&
        nextNow.join(',') == nextThen.join(',') &&
        (lines.length <= crowned.length ||
            !MonthFinalBoard.levelForCrown(
              lines[crowned.length].entry,
              lines.first.entry,
            ));
    if (same) {
      return Result.ok(settled);
    }

    final shown = lines.take(crowned.length + podium.length).toList();
    final order = <String>[
      for (var i = 0; i < shown.length; i++)
        '${i + 1}. ${shown[i].entry.displayName} '
            '(${shown[i].entry.totalPoints} نقطة، '
            '${shown[i].entry.exactCount} دقيقة)',
    ];
    final told = await _tellOnce(
      month,
      kind: 'changed',
      signature: [for (final line in shown) line.userId.value].join(','),
      title: 'تغيّر ترتيب شهر ${month.label} بعد تتويجه',
      body:
          'سُجّلت نتيجة أو عُدّلت بعد تتويج شهر ${month.label}، فصار أوائل '
          'ترتيبه النهائي:\n${order.join('\n')}\n'
          'التتويج والمنصة المسجّلان لا يتغيّران تلقائيًا: راجعهما.',
    );
    if (told is Err<void>) {
      return Result.err(told.error);
    }
    return Result.ok(
      AutoCrownOutcome(label: month.label, step: AutoCrownStep.changed),
    );
  }

  /// Tells the owner [title] / [body] about [month] unless he was already
  /// told [kind] / [signature].
  Future<Result<void>> _tellOnce(
    CrownDueMonth month, {
    required String kind,
    required String signature,
    required String title,
    required String body,
  }) async {
    final noted = await _store.noteOnce(
      season: month.seasonId,
      kind: kind,
      signature: signature,
    );
    if (noted is Err<bool>) {
      return Result.err(noted.error);
    }
    if (!(noted as Ok<bool>).value) {
      return const Result.ok(null);
    }
    return _owner.tell(title: title, body: body);
  }

  /// The owner as an admin: the crowning and the podium are his.
  Future<Result<AuthenticatedUser>> _ownerPrincipal() async {
    final ownerResult = await _owner.ownerId();
    if (ownerResult is Err<UserId?>) {
      return Result.err(ownerResult.error);
    }
    final owner = (ownerResult as Ok<UserId?>).value;
    if (owner == null) {
      return const Result.err(
        AppError.invariant(
          'champion.owner_missing',
          'No active admin account has the owner e-mail',
        ),
      );
    }
    return Result.ok(
      AuthenticatedUser(userId: owner, role: PlatformRole.admin),
    );
  }

  static String _names(List<ChampionCandidate> lines) =>
      lines.map((line) => line.entry.displayName).join(' و');
}
