import 'package:application/src/football_data/ports/live_score_board.dart';
import 'package:application/src/football_data/ports/match_details.dart';
import 'package:application/src/football_data/provider_sync_rules.dart';
import 'package:application/src/publisher/goal_details_match.dart';
import 'package:application/src/publisher/ports/publisher_outlets.dart';
import 'package:application/src/publisher/ports/publisher_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Whether the publisher runs, and whether it sends (`NUKHBA_PUBLISHER`).
enum PublisherMode {
  /// Nothing runs.
  off,

  /// Everything runs, pictures and words included, but nothing is sent: a
  /// post due is kept as [PostState.dryRun] for the admin to review.
  dryRun,

  /// Posts are sent.
  on;

  /// Parses `NUKHBA_PUBLISHER`: `on`, `dry_run`; anything else is [off].
  static PublisherMode parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'on':
        return PublisherMode.on;
      case 'dry_run':
      case 'dry-run':
      case 'dryrun':
        return PublisherMode.dryRun;
      default:
        return PublisherMode.off;
    }
  }
}

/// What one run of [PublisherTick] did.
final class PublisherTickReport {
  /// Creates the report.
  PublisherTickReport();

  /// Goals first seen.
  int seen = 0;

  /// Goals the feed took back.
  int withdrawn = 0;

  /// Goals confirmed.
  int confirmed = 0;

  /// Posts queued (goals, finals, corrections).
  int queued = 0;

  /// Posts sent, or kept in a dry run.
  int sent = 0;

  /// What went wrong or waits, for the log.
  final List<String> notes = <String>[];

  /// What an admin must look at, as `(subject, code, message)`: a goal the
  /// VAR took back after Instagram had it, a post that may be on a platform.
  final List<({String subject, String code, String message})> attention =
      <({String subject, String code, String message})>[];

  /// Whether anything happened.
  bool get isEmpty =>
      seen == 0 &&
      withdrawn == 0 &&
      confirmed == 0 &&
      queued == 0 &&
      sent == 0 &&
      notes.isEmpty &&
      attention.isEmpty;
}

/// System use-case: one minute of the sports publisher.
///
/// 1. For each covered match in play, the running score (the corrected
///    board, as the players see it) is read against the last score kept:
///    a new goal is stored pending, a goal the feed took back is withdrawn
///    (and corrected where it was posted). A match with no running score
///    is left as it is: no read is never 0-0.
/// 2. A pending goal that has stood its hold is confirmed: the provider is
///    asked for the scorer (a few times, a couple of minutes apart), the
///    picture is drawn and kept, and one post per platform that takes the
///    goal is queued under a unique key, so a goal is never queued twice.
/// 3. A covered match with a recorded result gets its final-result posts.
/// 4. Due posts are claimed and sent, each platform on its own: a platform
///    that fails never holds the others back.
/// 5. Posts published a day ago are asked for their reach and reactions.
///
/// Reads the schedule, the results and the running scores; writes only the
/// publisher's own tables. Never throws.
final class PublisherTick {
  /// Creates the use-case.
  PublisherTick({
    required PublisherStore store,
    required LiveScoreBoard board,
    required PublisherMode mode,
    required Map<PublishPlatform, PlatformPoster> posters,
    PublisherCardRenderer? renderer,
    PublisherCardHost? host,
    LiveGoalDetails? details,
    this.liveWindow = const Duration(hours: 3),
    this.detailsSpacing = const Duration(minutes: 2),
    this.maxDetailsTries = 3,
    this.claimLimit = 4,
    this.lease = const Duration(minutes: 3),
    this.maxAttempts = 5,
    this.metricsAfter = const Duration(hours: 24),
    this.metricsLimit = 4,
  }) : _store = store,
       _board = board,
       _mode = mode,
       _posters = posters,
       _renderer = renderer,
       _host = host,
       _details = details;

  final PublisherStore _store;
  final LiveScoreBoard _board;
  final PublisherMode _mode;
  final Map<PublishPlatform, PlatformPoster> _posters;
  final PublisherCardRenderer? _renderer;
  final PublisherCardHost? _host;
  final LiveGoalDetails? _details;

  /// How long after kickoff a match is watched for goals.
  final Duration liveWindow;

  /// The wait between two questions to the provider about one goal.
  final Duration detailsSpacing;

  /// How many times the provider is asked about one goal.
  final int maxDetailsTries;

  /// Posts claimed in one run.
  final int claimLimit;

  /// How long a claim holds.
  final Duration lease;

  /// Attempts before a post is given up.
  final int maxAttempts;

  /// How long after publishing a post's metrics are read.
  final Duration metricsAfter;

  /// Metrics read in one run.
  final int metricsLimit;

  /// Runs once at [now].
  Future<Result<PublisherTickReport>> call({required DateTime now}) async {
    final at = now.toUtc();
    final report = PublisherTickReport();
    final settingsRead = await _store.settings();
    if (settingsRead is Err<Map<PublishPlatform, PlatformIntensity>>) {
      return Result.err(settingsRead.error);
    }
    final settings =
        (settingsRead as Ok<Map<PublishPlatform, PlatformIntensity>>).value;
    final coverageRead = await _store.activeCoverage(
      now: at,
      liveFrom: at.subtract(liveWindow),
    );
    if (coverageRead is Err<List<CoveredFixture>>) {
      return Result.err(coverageRead.error);
    }
    for (final fixture in (coverageRead as Ok<List<CoveredFixture>>).value) {
      if (fixture.result == null) {
        await _watch(fixture, at, settings, report);
      } else if (!fixture.finalQueued) {
        await _queueFinal(fixture, at, settings, report);
      }
    }
    await _publishDue(at, settings, report);
    if (_mode == PublisherMode.on) {
      await _readMetrics(at, report);
    }
    return Result.ok(report);
  }

  Future<void> _watch(
    CoveredFixture fixture,
    DateTime now,
    Map<PublishPlatform, PlatformIntensity> settings,
    PublisherTickReport report,
  ) async {
    var known = fixture.known;
    final live = _board.read(<String>[fixture.fixtureId])[fixture.fixtureId];
    if (live != null) {
      final seen = ScoreLine(live.homeGoals, live.awayGoals);
      if (fixture.knownAt == null &&
          fixture.addedAt.isAfter(fixture.kickoffAt)) {
        // Picked after kickoff: the goals before the pick are not news.
        final kept = await _store.setKnown(fixture.fixtureId, seen, now);
        if (kept is Err<void>) {
          report.notes.add('baseline: ${kept.error.code}');
        }
        return;
      }
      final change = GoalWatch.diff(known, seen);
      for (final key in change.withdrawn) {
        final taken = await _store.withdrawGoal(fixture.fixtureId, key, now);
        if (taken is Err<StoredGoal?>) {
          report.notes.add('withdraw $key: ${taken.error.code}');
          return;
        }
        final goal = (taken as Ok<StoredGoal?>).value;
        if (goal == null) {
          continue;
        }
        report.withdrawn++;
        if (goal.state == StoredGoalState.confirmed) {
          await _queueCorrection(fixture, goal, seen, now, report);
        }
      }
      for (final step in change.added) {
        final added = await _store.addGoal(
          fixture.fixtureId,
          step,
          now,
          feedMinute: live.minute,
        );
        if (added is Err<void>) {
          report.notes.add('add ${step.key}: ${added.error.code}');
          return;
        }
        report.seen++;
      }
      if (!change.isEmpty || fixture.knownAt == null) {
        final kept = await _store.setKnown(fixture.fixtureId, seen, now);
        if (kept is Err<void>) {
          report.notes.add('keep score: ${kept.error.code}');
          return;
        }
      }
      known = seen;
    }

    final goalsRead = await _store.liveGoals(fixture.fixtureId);
    if (goalsRead is Err<List<StoredGoal>>) {
      report.notes.add(
        'goals of ${fixture.fixtureId}: ${goalsRead.error.code}',
      );
      return;
    }
    final hold = _shortestHold(settings);
    for (final goal in (goalsRead as Ok<List<StoredGoal>>).value) {
      if (goal.state != StoredGoalState.pending) {
        continue;
      }
      final stands = GoalWatch.confirmed(
        step: goal.step,
        seen: known,
        firstSeenAt: goal.firstSeenAt,
        now: now,
        hold: hold,
      );
      if (stands) {
        await _confirm(fixture, goal, now, hold, settings, report);
      }
    }
  }

  Future<void> _confirm(
    CoveredFixture fixture,
    StoredGoal goal,
    DateTime now,
    Duration hold,
    Map<PublishPlatform, PlatformIntensity> settings,
    PublisherTickReport report,
  ) async {
    final anyOn = settings.values.any((setting) => setting.enabled);
    GoalDetails? found;
    final source = _details;
    if (source != null && anyOn && goal.detailsTries < maxDetailsTries) {
      final dueAt = goal.firstSeenAt.add(
        hold + detailsSpacing * goal.detailsTries,
      );
      if (now.isBefore(dueAt)) {
        return;
      }
      await _store.noteDetailsTry(goal.id);
      final read = await source.eventsOf(
        fixtureId: fixture.fixtureId,
        leagueName: fixture.leagueName,
        kickoffAt: fixture.kickoffAt,
      );
      if (read case Ok<List<MatchEvent>?>(:final value) when value != null) {
        found = GoalDetailsMatch.find(goal.step, value);
      }
      if (found == null && goal.detailsTries + 1 < maxDetailsTries) {
        // Ask again in a while; providers often name a scorer late.
        return;
      }
    }

    final minuteLabel = found?.minuteLabel ?? goal.feedMinute?.toString();
    final moment = GoalMoment.of(
      goal.step,
      minute: GoalMoment.minuteOf(minuteLabel),
    );
    final facts = GoalPostFacts(
      league: fixture.leagueName,
      homeName: fixture.homeName,
      awayName: fixture.awayName,
      step: goal.step,
      moment: moment,
      scorer: found?.scorer,
      minuteLabel: minuteLabel,
      penalty: found?.penalty ?? false,
      ownGoal: found?.ownGoal ?? false,
    );

    final takers = <PublishPlatform>[
      for (final platform in PublishPlatform.values)
        if (_setting(settings, platform).admits(moment)) platform,
    ];
    final cardPath = 'goals/${fixture.fixtureId}/${goal.id}.jpg';
    final drawn = takers.isEmpty
        ? _Drawn.none
        : await _draw(
            fixture,
            cardPath,
            (home, away) => CardSpec(
              kind: CardKind.goal,
              league: fixture.leagueName,
              headline: PostCopy.headline(moment),
              homeName: fixture.homeName,
              awayName: fixture.awayName,
              homeBadge: home,
              awayBadge: away,
              score: goal.step.after,
              scoringHome: goal.step.home,
              scorer: _scorerLine(facts),
              minuteLabel: minuteLabel,
            ),
            report,
          );
    if (drawn == _Drawn.failed) {
      return;
    }
    final storedPath = drawn == _Drawn.kept ? cardPath : null;

    final day = riyadhDayOf(now);
    final posts = <NewPost>[];
    for (final platform in takers) {
      final setting = _setting(settings, platform);
      var state = PostState.queued;
      if (platform.delivery == PublishDelivery.manualShare) {
        // Prepared now for an admin; the day's cap is applied here, since
        // nothing is sent by the server.
        final today = await _store.goalPostsOn(platform, day);
        if (today case Ok(:final value) when value.count >= setting.dailyCap) {
          continue;
        }
        state = PostState.readyToShare;
      }
      posts.add(
        NewPost(
          dedupeKey: NewPost.goalKey(goal.id, platform),
          fixtureId: fixture.fixtureId,
          goalId: goal.id,
          kind: PostKind.goal,
          platform: platform,
          state: state,
          body: PostCopy.goal(
            platform,
            facts,
            seed: PostCopy.seedOf('${goal.id}:${platform.wire}'),
          ),
          cardPath: storedPath,
          riyadhDay: day,
          notBefore: goal.firstSeenAt.add(setting.hold),
        ),
      );
    }
    final queued = await _store.enqueue(posts);
    if (queued is Err<int>) {
      report.notes.add('queue ${goal.id}: ${queued.error.code}');
      return;
    }
    report.queued += (queued as Ok<int>).value;
    final confirmed = await _store.confirmGoal(
      goal.id,
      at: now,
      moment: moment,
      scorer: found?.scorer,
      minuteLabel: minuteLabel,
      penalty: found?.penalty ?? false,
      ownGoal: found?.ownGoal ?? false,
      cardPath: storedPath,
    );
    if (confirmed is Err<void>) {
      report.notes.add('confirm ${goal.id}: ${confirmed.error.code}');
      return;
    }
    report.confirmed++;
  }

  Future<void> _queueCorrection(
    CoveredFixture fixture,
    StoredGoal goal,
    ScoreLine scoreNow,
    DateTime now,
    PublisherTickReport report,
  ) async {
    final postedRead = await _store.postedPlatformsOf(goal.id);
    if (postedRead is Err<Set<PublishPlatform>>) {
      report.notes.add('posted of ${goal.id}: ${postedRead.error.code}');
      return;
    }
    final posted = (postedRead as Ok<Set<PublishPlatform>>).value;
    final facts = GoalCancelFacts(
      league: fixture.leagueName,
      homeName: fixture.homeName,
      awayName: fixture.awayName,
      cancelled: goal.step,
      scoreNow: scoreNow,
      minuteLabel: goal.minuteLabel,
    );
    final day = riyadhDayOf(now);
    final posts = <NewPost>[];
    for (final platform in posted) {
      if (platform == PublishPlatform.instagram) {
        report.attention.add((
          subject: '${fixture.homeName} - ${fixture.awayName}',
          code: 'publisher.instagram_goal_withdrawn',
          message:
              'ألغى حكم الفيديو هدفاً نُشر على إنستغرام '
              '(${goal.step.after}). لا يمكن تصحيحه آلياً: احذفه أو عدّل '
              'نصه من إنستغرام.',
        ));
        continue;
      }
      posts.add(
        NewPost(
          dedupeKey: NewPost.correctionKey(goal.id, platform),
          fixtureId: fixture.fixtureId,
          goalId: goal.id,
          kind: PostKind.correction,
          platform: platform,
          state: platform.delivery == PublishDelivery.manualShare
              ? PostState.readyToShare
              : PostState.queued,
          body: PostCopy.goalCancelled(platform, facts),
          riyadhDay: day,
          notBefore: now,
        ),
      );
    }
    if (posts.isEmpty) {
      return;
    }
    final queued = await _store.enqueue(posts);
    if (queued case Ok<int>(:final value)) {
      report.queued += value;
    } else if (queued case Err<int>(:final error)) {
      report.notes.add('queue correction ${goal.id}: ${error.code}');
    }
  }

  Future<void> _queueFinal(
    CoveredFixture fixture,
    DateTime now,
    Map<PublishPlatform, PlatformIntensity> settings,
    PublisherTickReport report,
  ) async {
    final result = fixture.result;
    if (result == null) {
      return;
    }
    final goalsRead = await _store.confirmedGoals(fixture.fixtureId);
    if (goalsRead is Err<List<StoredGoal>>) {
      report.notes.add(
        'goals of ${fixture.fixtureId}: ${goalsRead.error.code}',
      );
      return;
    }
    final homeScorers = <String>[];
    final awayScorers = <String>[];
    final lines = <String>[];
    for (final goal in (goalsRead as Ok<List<StoredGoal>>).value) {
      final scorer = goal.scorer;
      if (scorer == null) {
        continue;
      }
      final minute = goal.minuteLabel ?? '';
      final name = goal.ownGoal ? '$scorer (في مرماه)' : scorer;
      (goal.step.home ? homeScorers : awayScorers).add('$name|$minute');
      lines.add(minute.isEmpty ? name : "$name $minute'");
    }
    final facts = FinalPostFacts(
      league: fixture.leagueName,
      homeName: fixture.homeName,
      awayName: fixture.awayName,
      score: result,
      scorers: lines,
    );
    final takers = <PublishPlatform>[
      for (final platform in PublishPlatform.values)
        if (_setting(settings, platform).enabled &&
            _setting(settings, platform).finalResult)
          platform,
    ];
    final cardPath = 'finals/${fixture.fixtureId}.jpg';
    final drawn = takers.isEmpty
        ? _Drawn.none
        : await _draw(
            fixture,
            cardPath,
            (home, away) => CardSpec(
              kind: CardKind.finalResult,
              league: fixture.leagueName,
              headline: 'النتيجة النهائية',
              homeName: fixture.homeName,
              awayName: fixture.awayName,
              homeBadge: home,
              awayBadge: away,
              score: result,
              verdict: PostCopy.verdict(facts),
              homeScorers: homeScorers,
              awayScorers: awayScorers,
            ),
            report,
          );
    if (drawn == _Drawn.failed) {
      return;
    }
    final day = riyadhDayOf(now);
    final posts = <NewPost>[
      for (final platform in takers)
        NewPost(
          dedupeKey: NewPost.finalKey(fixture.fixtureId, platform),
          fixtureId: fixture.fixtureId,
          kind: PostKind.finalResult,
          platform: platform,
          state: platform.delivery == PublishDelivery.manualShare
              ? PostState.readyToShare
              : PostState.queued,
          body: PostCopy.finalResult(
            platform,
            facts,
            seed: PostCopy.seedOf('${fixture.fixtureId}:${platform.wire}'),
          ),
          cardPath: drawn == _Drawn.kept ? cardPath : null,
          riyadhDay: day,
          notBefore: now,
        ),
    ];
    final queued = await _store.enqueue(posts);
    if (queued is Err<int>) {
      report.notes.add(
        'queue final ${fixture.fixtureId}: ${queued.error.code}',
      );
      return;
    }
    report.queued += (queued as Ok<int>).value;
    final marked = await _store.markFinalQueued(fixture.fixtureId, now);
    if (marked is Err<void>) {
      report.notes.add('mark final ${fixture.fixtureId}: ${marked.error.code}');
    }
  }

  /// Draws the picture of [fixture] and keeps it at [path].
  Future<_Drawn> _draw(
    CoveredFixture fixture,
    String path,
    CardSpec Function(ClubBadge home, ClubBadge away) spec,
    PublisherTickReport report,
  ) async {
    final renderer = _renderer;
    final host = _host;
    if (renderer == null || host == null) {
      return _Drawn.none;
    }
    final ids = <String>[];
    for (final id in <String?>[fixture.homeTeamId, fixture.awayTeamId]) {
      if (id != null) {
        ids.add(id);
      }
    }
    final badgesRead = await _store.badges(ids);
    final badges = badgesRead is Ok<Map<String, StoredBadge>>
        ? badgesRead.value
        : const <String, StoredBadge>{};
    ClubBadge badgeOf(String? teamId, String name) {
      final stored = teamId == null ? null : badges[teamId];
      return stored == null
          ? ClubBadge.fallback(name)
          : ClubBadge.ofColour(
              clubName: name,
              fill: stored.fill,
              label: stored.label,
            );
    }

    final rendered = await renderer.render(
      spec(
        badgeOf(fixture.homeTeamId, fixture.homeName),
        badgeOf(fixture.awayTeamId, fixture.awayName),
      ),
    );
    if (rendered is Err<List<int>>) {
      report.notes.add('draw $path: ${rendered.error.code}');
      return _Drawn.failed;
    }
    final kept = await host.put(path, (rendered as Ok<List<int>>).value);
    if (kept is Err<void>) {
      report.notes.add('keep $path: ${kept.error.code}');
      return _Drawn.failed;
    }
    return _Drawn.kept;
  }

  Future<void> _publishDue(
    DateTime now,
    Map<PublishPlatform, PlatformIntensity> settings,
    PublisherTickReport report,
  ) async {
    final claimed = await _store.claimDue(
      now: now,
      limit: claimLimit,
      lease: lease,
    );
    if (claimed is Err<List<ClaimedPost>>) {
      report.notes.add('claim: ${claimed.error.code}');
      return;
    }
    for (final post in (claimed as Ok<List<ClaimedPost>>).value) {
      final setting = _setting(settings, post.platform);
      final (fate, attempted) = await _send(post, setting, now);
      if (fate is PostPublished ||
          (fate is PostEnded && fate.state == PostState.dryRun)) {
        report.sent++;
      }
      if (fate is PostEnded && fate.state == PostState.uncertain) {
        report.attention.add((
          subject: post.id,
          code: 'publisher.post_uncertain',
          message:
              'انقطع الاتصال بعد إرسال منشور إلى ${post.platform.wire}: '
              'تحقق من الصفحة قبل إعادة المحاولة من اللوحة.',
        ));
      }
      final finished = await _store.finish(
        post.id,
        fate,
        now,
        attempted: attempted,
      );
      if (finished is Err<void>) {
        report.notes.add('finish ${post.id}: ${finished.error.code}');
      }
    }
  }

  Future<(PostFate, bool)> _send(
    ClaimedPost post,
    PlatformIntensity setting,
    DateTime now,
  ) async {
    if (!setting.enabled) {
      return (const PostEnded(PostState.skipped, 'platform_off'), false);
    }
    if (post.kind == PostKind.goal) {
      final goalId = post.goalId;
      if (goalId != null) {
        final stands = await _store.goalStands(goalId);
        if (stands case Ok<bool>(:final value) when !value) {
          return (const PostEnded(PostState.skipped, 'goal_withdrawn'), false);
        }
        if (stands is Err<bool>) {
          return (PostRetry(now.add(lease), stands.error.code), false);
        }
      }
      final today = await _store.goalPostsOn(post.platform, riyadhDayOf(now));
      if (today is Err<({int count, DateTime? lastAt})>) {
        return (PostRetry(now.add(lease), today.error.code), false);
      }
      final day = (today as Ok<({int count, DateTime? lastAt})>).value;
      switch (GoalGate.decide(
        intensity: setting,
        goalPostsToday: day.count,
        lastGoalPostAt: day.lastAt,
        now: now,
      )) {
        case GoalGateFull():
          return (const PostEnded(PostState.skipped, 'daily_cap'), false);
        case GoalGateWait(:final at):
          return (PostRetry(at, 'min_gap'), false);
        case GoalGateOpen():
          break;
      }
    }
    if (_mode != PublisherMode.on) {
      return (const PostEnded(PostState.dryRun, 'dry_run'), false);
    }
    final poster = _posters[post.platform];
    if (poster == null) {
      return (const PostEnded(PostState.failed, 'no_account'), false);
    }
    final path = post.cardPath;
    final host = _host;
    final PosterOutcome outcome;
    if (path == null || host == null) {
      // A correction is words only; a goal or a result needs its picture.
      if (post.kind != PostKind.correction) {
        return (const PostEnded(PostState.failed, 'no_card'), false);
      }
      outcome = await poster.post(text: post.body);
    } else {
      final image = await host.get(path);
      if (image is Err<List<int>>) {
        return _retryOrFail(post, now, 'card_unreadable', lease);
      }
      outcome = await poster.post(
        text: post.body,
        image: (image as Ok<List<int>>).value,
        imageUrl: host.publicUrl(path),
      );
    }
    switch (outcome) {
      case PosterPublished(:final externalId):
        return (PostPublished(externalId), true);
      case PosterRetry(:final reason, :final after):
        return _retryOrFail(post, now, reason, after);
      case PosterRejected(:final reason):
        return (PostEnded(PostState.failed, reason), true);
      case PosterUncertain(:final reason):
        return (PostEnded(PostState.uncertain, reason), true);
    }
  }

  (PostFate, bool) _retryOrFail(
    ClaimedPost post,
    DateTime now,
    String reason,
    Duration after,
  ) {
    final made = post.attempts + 1;
    if (made >= maxAttempts) {
      return (PostEnded(PostState.failed, reason), true);
    }
    // 1x, 2x, 4x... the wait asked for, at most half an hour.
    var wait = after * (1 << (made - 1));
    if (wait > const Duration(minutes: 30)) {
      wait = const Duration(minutes: 30);
    }
    return (PostRetry(now.add(wait), reason), true);
  }

  Future<void> _readMetrics(DateTime now, PublisherTickReport report) async {
    final due = await _store.metricsDue(
      before: now.subtract(metricsAfter),
      limit: metricsLimit,
    );
    if (due is Err<List<MetricsDue>>) {
      report.notes.add('metrics due: ${due.error.code}');
      return;
    }
    for (final entry in (due as Ok<List<MetricsDue>>).value) {
      final poster = _posters[entry.platform];
      if (poster == null) {
        continue;
      }
      final read = await poster.metrics(entry.externalId);
      if (read is Err<PostMetrics?>) {
        report.notes.add('metrics ${entry.postId}: ${read.error.code}');
        continue;
      }
      final metrics = (read as Ok<PostMetrics?>).value ?? const PostMetrics();
      final saved = await _store.saveMetrics(entry.postId, metrics, now);
      if (saved is Err<void>) {
        report.notes.add('save metrics ${entry.postId}: ${saved.error.code}');
      }
    }
  }

  static PlatformIntensity _setting(
    Map<PublishPlatform, PlatformIntensity> settings,
    PublishPlatform platform,
  ) => settings[platform] ?? PlatformIntensity.defaults(platform);

  Duration _shortestHold(Map<PublishPlatform, PlatformIntensity> settings) {
    Duration? shortest;
    for (final setting in settings.values) {
      if (!setting.enabled) {
        continue;
      }
      if (shortest == null || setting.hold < shortest) {
        shortest = setting.hold;
      }
    }
    return shortest ?? const Duration(minutes: 3);
  }

  static String? _scorerLine(GoalPostFacts facts) {
    final scorer = facts.scorer;
    if (scorer == null) {
      return null;
    }
    if (facts.ownGoal) {
      return '$scorer (في مرماه)';
    }
    if (facts.penalty) {
      return '$scorer (ركلة جزاء)';
    }
    return scorer;
  }
}

enum _Drawn {
  /// Drawn and kept.
  kept,

  /// No renderer or store is wired (tests, a server without them).
  none,

  /// Drawing or keeping failed; the step is tried again next run.
  failed,
}
