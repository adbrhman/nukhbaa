import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A goal row as the fake keeps it.
final class FakeGoal {
  FakeGoal({
    required this.id,
    required this.fixtureId,
    required this.step,
    required this.firstSeenAt,
    this.feedMinute,
  });

  final String id;
  final String fixtureId;
  final GoalStep step;
  final DateTime firstSeenAt;
  final int? feedMinute;
  StoredGoalState state = StoredGoalState.pending;
  GoalMoment? moment;
  String? scorer;
  String? minuteLabel;
  bool penalty = false;
  bool ownGoal = false;
  int detailsTries = 0;
  String? cardPath;

  StoredGoal get view => StoredGoal(
    id: id,
    fixtureId: fixtureId,
    step: step,
    state: state,
    firstSeenAt: firstSeenAt,
    feedMinute: feedMinute,
    moment: moment,
    scorer: scorer,
    minuteLabel: minuteLabel,
    penalty: penalty,
    ownGoal: ownGoal,
    detailsTries: detailsTries,
    cardPath: cardPath,
  );
}

/// A post row as the fake keeps it.
final class FakePost {
  FakePost(this.id, this.post) : state = post.state, notBefore = post.notBefore;

  final String id;
  final NewPost post;
  PostState state;
  DateTime notBefore;
  DateTime? nextAttemptAt;
  DateTime? claimedUntil;
  int attempts = 0;
  String? externalId;
  String? error;
  DateTime? publishedAt;
}

/// A coverage row as the fake keeps it.
final class FakeCoverage {
  FakeCoverage({
    required this.fixtureId,
    required this.homeName,
    required this.awayName,
    required this.leagueName,
    required this.kickoffAt,
    required this.addedAt,
    this.homeTeamId,
    this.awayTeamId,
  });

  final String fixtureId;
  final String homeName;
  final String awayName;
  final String leagueName;
  final DateTime kickoffAt;
  DateTime addedAt;
  final String? homeTeamId;
  final String? awayTeamId;
  ScoreLine known = ScoreLine.nil;
  DateTime? knownAt;
  ScoreLine? result;
  bool finalQueued = false;
  bool stopped = false;
}

/// An in-memory [PublisherStore] that keeps the rules the SQL keeps: one
/// live goal per key, one post per dedupe key, a claim per post, an
/// interrupted claim made uncertain.
final class FakePublisherStore implements PublisherStore {
  final Map<PublishPlatform, PlatformIntensity> stored =
      <PublishPlatform, PlatformIntensity>{};
  final Map<String, FakeCoverage> coverage = <String, FakeCoverage>{};
  final List<FakeGoal> goals = <FakeGoal>[];
  final List<FakePost> posts = <FakePost>[];
  final Map<String, StoredBadge> badgeRows = <String, StoredBadge>{};
  final Map<String, PostMetrics> metrics = <String, PostMetrics>{};
  int _ids = 0;

  String _id(String prefix) => '$prefix-${++_ids}';

  /// Turns [platform] on with its defaults and [change] applied.
  void enable(
    PublishPlatform platform, {
    PlatformIntensity Function(PlatformIntensity)? change,
  }) {
    final turned = PlatformIntensity.defaults(platform).copyWith(enabled: true);
    stored[platform] = change == null ? turned : change(turned);
  }

  List<FakePost> postsOf(PublishPlatform platform) => <FakePost>[
    for (final post in posts)
      if (post.post.platform == platform) post,
  ];

  @override
  Future<Result<Map<PublishPlatform, PlatformIntensity>>> settings() async =>
      Result.ok(<PublishPlatform, PlatformIntensity>{
        for (final platform in PublishPlatform.values)
          platform: stored[platform] ?? PlatformIntensity.defaults(platform),
      });

  @override
  Future<Result<void>> saveSetting(
    PlatformIntensity intensity,
    String actorId,
  ) async {
    stored[intensity.platform] = intensity;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<CoveredFixture>>> activeCoverage({
    required DateTime now,
    required DateTime liveFrom,
  }) async => Result.ok(<CoveredFixture>[
    for (final row in coverage.values)
      if (!row.stopped &&
          ((row.result == null &&
                  !row.kickoffAt.isBefore(liveFrom) &&
                  !row.kickoffAt.isAfter(
                    now.add(const Duration(minutes: 5)),
                  )) ||
              (row.result != null && !row.finalQueued)))
        CoveredFixture(
          fixtureId: row.fixtureId,
          homeName: row.homeName,
          awayName: row.awayName,
          homeTeamId: row.homeTeamId,
          awayTeamId: row.awayTeamId,
          leagueName: row.leagueName,
          kickoffAt: row.kickoffAt,
          known: row.known,
          knownAt: row.knownAt,
          addedAt: row.addedAt,
          result: row.result,
          finalQueued: row.finalQueued,
        ),
  ]);

  @override
  Future<Result<void>> setKnown(
    String fixtureId,
    ScoreLine score,
    DateTime at,
  ) async {
    coverage[fixtureId]!
      ..known = score
      ..knownAt = at;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<StoredGoal>>> liveGoals(String fixtureId) async =>
      Result.ok(<StoredGoal>[
        for (final goal in goals)
          if (goal.fixtureId == fixtureId &&
              goal.state != StoredGoalState.withdrawn)
            goal.view,
      ]);

  @override
  Future<Result<List<StoredGoal>>> confirmedGoals(String fixtureId) async =>
      Result.ok(<StoredGoal>[
        for (final goal in goals)
          if (goal.fixtureId == fixtureId &&
              goal.state == StoredGoalState.confirmed)
            goal.view,
      ]);

  @override
  Future<Result<void>> addGoal(
    String fixtureId,
    GoalStep step,
    DateTime at, {
    int? feedMinute,
  }) async {
    final live = goals.any(
      (goal) =>
          goal.fixtureId == fixtureId &&
          goal.step.key == step.key &&
          goal.state != StoredGoalState.withdrawn,
    );
    if (!live) {
      goals.add(
        FakeGoal(
          id: _id('goal'),
          fixtureId: fixtureId,
          step: step,
          firstSeenAt: at,
          feedMinute: feedMinute,
        ),
      );
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<StoredGoal?>> withdrawGoal(
    String fixtureId,
    String key,
    DateTime at,
  ) async {
    for (final goal in goals) {
      if (goal.fixtureId == fixtureId &&
          goal.step.key == key &&
          goal.state != StoredGoalState.withdrawn) {
        final before = goal.view;
        goal.state = StoredGoalState.withdrawn;
        return Result.ok(before);
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> noteDetailsTry(String goalId) async {
    goals.firstWhere((goal) => goal.id == goalId).detailsTries++;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> confirmGoal(
    String goalId, {
    required DateTime at,
    required GoalMoment moment,
    String? scorer,
    String? minuteLabel,
    bool penalty = false,
    bool ownGoal = false,
    String? cardPath,
  }) async {
    final goal = goals.firstWhere((goal) => goal.id == goalId);
    if (goal.state == StoredGoalState.pending) {
      goal
        ..state = StoredGoalState.confirmed
        ..moment = moment
        ..scorer = scorer
        ..minuteLabel = minuteLabel
        ..penalty = penalty
        ..ownGoal = ownGoal
        ..cardPath = cardPath;
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> enqueue(List<NewPost> posts) async {
    var added = 0;
    for (final post in posts) {
      if (this.posts.any((row) => row.post.dedupeKey == post.dedupeKey)) {
        continue;
      }
      this.posts.add(FakePost(_id('post'), post));
      added++;
    }
    return Result.ok(added);
  }

  @override
  Future<Result<void>> markFinalQueued(String fixtureId, DateTime at) async {
    coverage[fixtureId]!.finalQueued = true;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<ClaimedPost>>> claimDue({
    required DateTime now,
    required int limit,
    required Duration lease,
  }) async {
    for (final row in posts) {
      final until = row.claimedUntil;
      if (row.state == PostState.queued &&
          until != null &&
          until.isBefore(now)) {
        row
          ..state = PostState.uncertain
          ..error = 'interrupted'
          ..claimedUntil = null;
      }
    }
    final claimed = <ClaimedPost>[];
    for (final row in posts) {
      if (claimed.length >= limit) {
        break;
      }
      final next = row.nextAttemptAt;
      if (row.state == PostState.queued &&
          row.claimedUntil == null &&
          !row.notBefore.isAfter(now) &&
          (next == null || !next.isAfter(now))) {
        row.claimedUntil = now.add(lease);
        claimed.add(
          ClaimedPost(
            id: row.id,
            fixtureId: row.post.fixtureId,
            goalId: row.post.goalId,
            kind: row.post.kind,
            platform: row.post.platform,
            body: row.post.body,
            cardPath: row.post.cardPath,
            attempts: row.attempts,
          ),
        );
      }
    }
    return Result.ok(claimed);
  }

  @override
  Future<Result<void>> finish(
    String postId,
    PostFate fate,
    DateTime at, {
    required bool attempted,
  }) async {
    final row = posts.firstWhere((post) => post.id == postId);
    row
      ..claimedUntil = null
      ..attempts = row.attempts + (attempted ? 1 : 0);
    switch (fate) {
      case PostPublished(:final externalId):
        row
          ..state = PostState.published
          ..externalId = externalId
          ..publishedAt = at
          ..error = null
          ..nextAttemptAt = null;
      case PostRetry(at: final retryAt, :final reason):
        row
          ..state = PostState.queued
          ..nextAttemptAt = retryAt
          ..error = reason;
      case PostEnded(state: final ended, :final reason):
        row
          ..state = ended
          ..error = reason
          ..nextAttemptAt = null
          ..publishedAt = ended == PostState.dryRun ? at : row.publishedAt;
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<({int count, DateTime? lastAt})>> goalPostsOn(
    PublishPlatform platform,
    DateTime riyadhDay,
  ) async {
    const counted = <PostState>{
      PostState.published,
      PostState.dryRun,
      PostState.readyToShare,
      PostState.shared,
    };
    var count = 0;
    DateTime? last;
    for (final row in posts) {
      if (row.post.platform == platform &&
          row.post.kind == PostKind.goal &&
          row.post.riyadhDay == riyadhDay &&
          counted.contains(row.state)) {
        count++;
        final at = row.publishedAt ?? row.post.notBefore;
        if (last == null || at.isAfter(last)) {
          last = at;
        }
      }
    }
    return Result.ok((count: count, lastAt: last));
  }

  @override
  Future<Result<Set<PublishPlatform>>> postedPlatformsOf(String goalId) async =>
      Result.ok(<PublishPlatform>{
        for (final row in posts)
          if (row.post.goalId == goalId &&
              row.post.kind == PostKind.goal &&
              (row.state == PostState.published ||
                  row.state == PostState.shared ||
                  row.state == PostState.dryRun))
            row.post.platform,
      });

  @override
  Future<Result<bool>> goalStands(String goalId) async => Result.ok(
    goals.any(
      (goal) => goal.id == goalId && goal.state == StoredGoalState.confirmed,
    ),
  );

  @override
  Future<Result<Map<String, StoredBadge>>> badges(
    Iterable<String> teamIds,
  ) async => Result.ok(<String, StoredBadge>{
    for (final id in teamIds)
      if (badgeRows[id] case final badge?) id: badge,
  });

  @override
  Future<Result<List<MetricsDue>>> metricsDue({
    required DateTime before,
    required int limit,
  }) async => Result.ok(
    <MetricsDue>[
      for (final row in posts)
        if (row.state == PostState.published &&
            row.externalId != null &&
            !metrics.containsKey(row.id) &&
            row.publishedAt!.isBefore(before))
          MetricsDue(
            postId: row.id,
            platform: row.post.platform,
            externalId: row.externalId!,
          ),
    ].take(limit).toList(),
  );

  @override
  Future<Result<void>> saveMetrics(
    String postId,
    PostMetrics metrics,
    DateTime at,
  ) async {
    this.metrics[postId] = metrics;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<CoverageCandidate>>> candidates({
    required DateTime from,
    required DateTime to,
  }) async => Result.ok(<CoverageCandidate>[
    for (final row in coverage.values)
      CoverageCandidate(
        fixtureId: row.fixtureId,
        homeName: row.homeName,
        awayName: row.awayName,
        leagueName: row.leagueName,
        kickoffAt: row.kickoffAt,
        covered: !row.stopped,
      ),
  ]);

  @override
  Future<Result<bool>> cover(
    String fixtureId,
    String actorId,
    DateTime at,
  ) async {
    final row = coverage[fixtureId];
    if (row == null) {
      return const Result.ok(false);
    }
    if (row.stopped) {
      row
        ..stopped = false
        ..addedAt = at
        ..knownAt = null;
    }
    return const Result.ok(true);
  }

  @override
  Future<Result<void>> stopCovering(String fixtureId, DateTime at) async {
    coverage[fixtureId]?.stopped = true;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<PostView>>> recentPosts({required int limit}) async =>
      Result.ok(<PostView>[
        for (final row in posts.reversed.take(limit)) _view(row),
      ]);

  @override
  Future<Result<PostView?>> post(String postId) async {
    for (final row in posts) {
      if (row.id == postId) {
        return Result.ok(_view(row));
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> movePost(
    String postId, {
    required Set<PostState> from,
    required PostState to,
    required DateTime at,
  }) async {
    for (final row in posts) {
      if (row.id == postId && from.contains(row.state)) {
        row
          ..state = to
          ..claimedUntil = null
          ..nextAttemptAt = null;
        if (to == PostState.queued) {
          row
            ..error = null
            ..notBefore = row.notBefore.isBefore(at) ? row.notBefore : at;
        }
        return const Result.ok(true);
      }
    }
    return const Result.ok(false);
  }

  @override
  Future<Result<List<StoredBadge>>> allBadges() async =>
      Result.ok(badgeRows.values.toList());

  @override
  Future<Result<bool>> saveBadge(
    String teamId, {
    required String fill,
    required String? label,
    required String actorId,
  }) async {
    badgeRows[teamId] = StoredBadge(
      teamId: teamId,
      teamName: '',
      fill: fill,
      label: label,
    );
    return const Result.ok(true);
  }

  PostView _view(FakePost row) => PostView(
    id: row.id,
    fixtureId: row.post.fixtureId,
    matchLabel: '',
    kind: row.post.kind,
    platform: row.post.platform,
    state: row.state,
    body: row.post.body,
    cardPath: row.post.cardPath,
    externalId: row.externalId,
    error: row.error,
    createdAt: row.post.notBefore,
    publishedAt: row.publishedAt,
    attempts: row.attempts,
  );
}
