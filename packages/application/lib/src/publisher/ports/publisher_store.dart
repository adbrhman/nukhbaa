import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A match an admin picked for the publisher, as the publisher needs it.
final class CoveredFixture {
  /// Creates the match.
  const CoveredFixture({
    required this.fixtureId,
    required this.homeName,
    required this.awayName,
    required this.leagueName,
    required this.kickoffAt,
    required this.known,
    required this.addedAt,
    this.knownAt,
    this.homeTeamId,
    this.awayTeamId,
    this.result,
    this.finalQueued = false,
  });

  /// The app's fixture id.
  final String fixtureId;

  /// The home club's name on the schedule.
  final String homeName;

  /// The away club's name on the schedule.
  final String awayName;

  /// The home club's catalog id, when the schedule has one.
  final String? homeTeamId;

  /// The away club's catalog id, when the schedule has one.
  final String? awayTeamId;

  /// The competition's name; empty when the match has none.
  final String leagueName;

  /// Kickoff, UTC.
  final DateTime kickoffAt;

  /// The score the publisher last read for it (0-0 before any read).
  final ScoreLine known;

  /// When it was last read; null before the first read.
  final DateTime? knownAt;

  /// When an admin picked it (the last time, after a stop).
  final DateTime addedAt;

  /// The recorded result, once there is one.
  final ScoreLine? result;

  /// Whether its final-result posts were already queued.
  final bool finalQueued;
}

/// Where a goal the publisher saw stands.
enum StoredGoalState {
  /// Seen on the feed, waiting for its hold.
  pending('pending'),

  /// Stood its hold; its posts were queued.
  confirmed('confirmed'),

  /// The feed took it back.
  withdrawn('withdrawn');

  const StoredGoalState(this.wire);

  /// The stored name.
  final String wire;

  /// The state named [wire]; [pending] for a name not known here.
  static StoredGoalState fromWire(String wire) {
    for (final state in StoredGoalState.values) {
      if (state.wire == wire) {
        return state;
      }
    }
    return StoredGoalState.pending;
  }
}

/// A goal the publisher saw, as stored.
final class StoredGoal {
  /// Creates the goal.
  const StoredGoal({
    required this.id,
    required this.fixtureId,
    required this.step,
    required this.state,
    required this.firstSeenAt,
    this.feedMinute,
    this.moment,
    this.scorer,
    this.minuteLabel,
    this.penalty = false,
    this.ownGoal = false,
    this.detailsTries = 0,
    this.cardPath,
  });

  /// Its id.
  final String id;

  /// Its match.
  final String fixtureId;

  /// The goal.
  final GoalStep step;

  /// Where it stands.
  final StoredGoalState state;

  /// When the feed first showed it.
  final DateTime firstSeenAt;

  /// The feed's minute when it was first seen, if the feed gave one.
  final int? feedMinute;

  /// What it meant, once confirmed.
  final GoalMoment? moment;

  /// The player, once the provider named him.
  final String? scorer;

  /// The clock label, from the provider, or the feed's minute.
  final String? minuteLabel;

  /// Scored from the spot.
  final bool penalty;

  /// An own goal.
  final bool ownGoal;

  /// How many times the provider was asked about it.
  final int detailsTries;

  /// Its picture in the card store, once drawn.
  final String? cardPath;
}

/// What a post is about.
enum PostKind {
  /// A goal.
  goal('goal'),

  /// The final result.
  finalResult('final'),

  /// A posted goal the VAR ruled out.
  correction('correction');

  const PostKind(this.wire);

  /// The stored name.
  final String wire;

  /// The kind named [wire]; [goal] for a name not known here.
  static PostKind fromWire(String wire) {
    for (final kind in PostKind.values) {
      if (kind.wire == wire) {
        return kind;
      }
    }
    return PostKind.goal;
  }
}

/// Where a post stands.
enum PostState {
  /// Waiting for its time.
  queued('queued'),

  /// On the platform.
  published('published'),

  /// Prepared in a dry run; nothing was sent.
  dryRun('dry_run'),

  /// Prepared for an admin to share by hand (X).
  readyToShare('ready_to_share'),

  /// An admin said he shared it.
  shared('shared'),

  /// The platform refused it, or it ran out of attempts.
  failed('failed'),

  /// The request was cut after it was sent: it may or may not be on the
  /// platform, so it is never sent again by itself.
  uncertain('uncertain'),

  /// Not sent: the platform was turned off, the day was full, or the goal
  /// was withdrawn before its turn.
  skipped('skipped'),

  /// An admin cancelled it.
  cancelled('cancelled');

  const PostState(this.wire);

  /// The stored name.
  final String wire;

  /// The state named [wire]; [failed] for a name not known here.
  static PostState fromWire(String wire) {
    for (final state in PostState.values) {
      if (state.wire == wire) {
        return state;
      }
    }
    return PostState.failed;
  }
}

/// A post to queue.
final class NewPost {
  /// Creates the post.
  const NewPost({
    required this.dedupeKey,
    required this.fixtureId,
    required this.kind,
    required this.platform,
    required this.state,
    required this.body,
    required this.riyadhDay,
    required this.notBefore,
    this.goalId,
    this.cardPath,
  });

  /// Unique per post: `goal:<goal id>:<platform>`, `final:<fixture
  /// id>:<platform>`, `correction:<goal id>:<platform>`.
  final String dedupeKey;

  /// Its match.
  final String fixtureId;

  /// Its goal, for a goal post or a correction.
  final String? goalId;

  /// What it is about.
  final PostKind kind;

  /// Where it goes.
  final PublishPlatform platform;

  /// [PostState.queued] or [PostState.readyToShare].
  final PostState state;

  /// The words.
  final String body;

  /// The picture in the card store, if it has one.
  final String? cardPath;

  /// The Riyadh day it counts in (`yyyy-mm-dd` at midnight UTC).
  final DateTime riyadhDay;

  /// Not sent before then.
  final DateTime notBefore;

  /// The key of a goal post.
  static String goalKey(String goalId, PublishPlatform platform) =>
      'goal:$goalId:${platform.wire}';

  /// The key of a final-result post.
  static String finalKey(String fixtureId, PublishPlatform platform) =>
      'final:$fixtureId:${platform.wire}';

  /// The key of a correction.
  static String correctionKey(String goalId, PublishPlatform platform) =>
      'correction:$goalId:${platform.wire}';
}

/// A queued post claimed for sending.
final class ClaimedPost {
  /// Creates the post.
  const ClaimedPost({
    required this.id,
    required this.fixtureId,
    required this.kind,
    required this.platform,
    required this.body,
    required this.attempts,
    this.goalId,
    this.cardPath,
  });

  /// Its id.
  final String id;

  /// Its match.
  final String fixtureId;

  /// Its goal, for a goal post or a correction.
  final String? goalId;

  /// What it is about.
  final PostKind kind;

  /// Where it goes.
  final PublishPlatform platform;

  /// The words.
  final String body;

  /// The picture in the card store, if it has one.
  final String? cardPath;

  /// The attempts made before this one.
  final int attempts;
}

/// How a claimed post ended this time.
sealed class PostFate {
  const PostFate();
}

/// On the platform as [externalId].
final class PostPublished extends PostFate {
  /// Creates the fate.
  const PostPublished(this.externalId);

  /// The platform's id of the post.
  final String externalId;
}

/// Back in the queue until [at].
final class PostRetry extends PostFate {
  /// Creates the fate.
  const PostRetry(this.at, this.reason);

  /// When it is tried again.
  final DateTime at;

  /// Why.
  final String reason;
}

/// Done in [state] ([PostState.dryRun], [PostState.failed],
/// [PostState.uncertain] or [PostState.skipped]) for [reason].
final class PostEnded extends PostFate {
  /// Creates the fate.
  const PostEnded(this.state, this.reason);

  /// Where it ends.
  final PostState state;

  /// Why.
  final String reason;
}

/// A post as the admin panel lists it.
final class PostView {
  /// Creates the view.
  const PostView({
    required this.id,
    required this.fixtureId,
    required this.matchLabel,
    required this.kind,
    required this.platform,
    required this.state,
    required this.body,
    required this.createdAt,
    required this.attempts,
    this.cardPath,
    this.externalId,
    this.error,
    this.publishedAt,
    this.reach,
    this.reactions,
    this.comments,
    this.shares,
  });

  /// Its id.
  final String id;

  /// Its match.
  final String fixtureId;

  /// «الهلال - النصر».
  final String matchLabel;

  /// What it is about.
  final PostKind kind;

  /// Where it goes.
  final PublishPlatform platform;

  /// Where it stands.
  final PostState state;

  /// The words.
  final String body;

  /// The picture, if it has one.
  final String? cardPath;

  /// The platform's id, once published.
  final String? externalId;

  /// The last error.
  final String? error;

  /// When it was queued.
  final DateTime createdAt;

  /// When it went out.
  final DateTime? publishedAt;

  /// The attempts made.
  final int attempts;

  /// Accounts reached, when the platform reported it.
  final int? reach;

  /// Reactions or likes, when reported.
  final int? reactions;

  /// Comments, when reported.
  final int? comments;

  /// Shares, when reported.
  final int? shares;
}

/// A match the admin may pick, for the panel.
final class CoverageCandidate {
  /// Creates the candidate.
  const CoverageCandidate({
    required this.fixtureId,
    required this.homeName,
    required this.awayName,
    required this.leagueName,
    required this.kickoffAt,
    required this.covered,
  });

  /// The app's fixture id.
  final String fixtureId;

  /// The home club.
  final String homeName;

  /// The away club.
  final String awayName;

  /// The competition; empty when none.
  final String leagueName;

  /// Kickoff, UTC.
  final DateTime kickoffAt;

  /// Whether the publisher covers it.
  final bool covered;
}

/// A club's badge as an admin set it.
final class StoredBadge {
  /// Creates the badge.
  const StoredBadge({
    required this.teamId,
    required this.teamName,
    required this.fill,
    this.label,
  });

  /// The catalog id.
  final String teamId;

  /// The catalog name.
  final String teamName;

  /// `#RRGGBB`.
  final String fill;

  /// The words on the disc, when the admin set them.
  final String? label;
}

/// Reach and reactions read back from a post.
final class PostMetrics {
  /// Creates the reading.
  const PostMetrics({
    this.reach,
    this.reactions,
    this.comments,
    this.shares,
    this.raw = const <String, Object?>{},
  });

  /// Accounts reached.
  final int? reach;

  /// Reactions or likes.
  final int? reactions;

  /// Comments.
  final int? comments;

  /// Shares.
  final int? shares;

  /// What the platform answered.
  final Map<String, Object?> raw;
}

/// A published post whose metrics are due.
final class MetricsDue {
  /// Creates the entry.
  const MetricsDue({
    required this.postId,
    required this.platform,
    required this.externalId,
  });

  /// The post.
  final String postId;

  /// Its platform.
  final PublishPlatform platform;

  /// The platform's id.
  final String externalId;
}

/// Everything the publisher keeps (migration 0200). Never throws.
abstract interface class PublisherStore {
  /// Each platform's setting; a platform never set reads its defaults.
  Future<Result<Map<PublishPlatform, PlatformIntensity>>> settings();

  /// Stores [intensity] for its platform, set by [actorId].
  Future<Result<void>> saveSetting(PlatformIntensity intensity, String actorId);

  /// The covered matches that may need work at [now]: kicked off from
  /// [liveFrom] on and not past [now] plus a few minutes, or with a result
  /// whose final posts are not queued yet (kicked off within the last two
  /// days). Hidden and test matches are left out.
  Future<Result<List<CoveredFixture>>> activeCoverage({
    required DateTime now,
    required DateTime liveFrom,
  });

  /// Keeps [score] as the last read of [fixtureId], at [at].
  Future<Result<void>> setKnown(String fixtureId, ScoreLine score, DateTime at);

  /// The goals of [fixtureId] that are not withdrawn.
  Future<Result<List<StoredGoal>>> liveGoals(String fixtureId);

  /// The confirmed goals of [fixtureId], in order.
  Future<Result<List<StoredGoal>>> confirmedGoals(String fixtureId);

  /// Stores [step] of [fixtureId] first seen at [at]; a live goal of the
  /// same key already stored is left as it is.
  Future<Result<void>> addGoal(
    String fixtureId,
    GoalStep step,
    DateTime at, {
    int? feedMinute,
  });

  /// Marks the live goal [key] of [fixtureId] withdrawn at [at]; returns it
  /// as it was, or null when there was none.
  Future<Result<StoredGoal?>> withdrawGoal(
    String fixtureId,
    String key,
    DateTime at,
  );

  /// Counts one more question to the provider about [goalId].
  Future<Result<void>> noteDetailsTry(String goalId);

  /// Confirms [goalId] at [at] with what was learnt about it.
  Future<Result<void>> confirmGoal(
    String goalId, {
    required DateTime at,
    required GoalMoment moment,
    String? scorer,
    String? minuteLabel,
    bool penalty = false,
    bool ownGoal = false,
    String? cardPath,
  });

  /// Queues [posts]; a post whose key is already queued is left as it is.
  /// Returns how many were new.
  Future<Result<int>> enqueue(List<NewPost> posts);

  /// Marks the final posts of [fixtureId] queued at [at].
  Future<Result<void>> markFinalQueued(String fixtureId, DateTime at);

  /// Claims up to [limit] queued posts due at [now] for [lease].
  ///
  /// A queued post whose earlier claim ran out without being finished (the
  /// server stopped while it was being sent) is marked
  /// [PostState.uncertain] first, never claimed again: it may be on the
  /// platform already.
  Future<Result<List<ClaimedPost>>> claimDue({
    required DateTime now,
    required int limit,
    required Duration lease,
  });

  /// Records how claimed post [postId] ended at [at], and releases its
  /// claim. [attempted]: the platform was called this time, which counts
  /// one attempt.
  Future<Result<void>> finish(
    String postId,
    PostFate fate,
    DateTime at, {
    required bool attempted,
  });

  /// The goal posts [platform] sent or prepared on [riyadhDay], and when
  /// the last of them went out.
  Future<Result<({int count, DateTime? lastAt})>> goalPostsOn(
    PublishPlatform platform,
    DateTime riyadhDay,
  );

  /// The platforms where a post about [goalId] is published or shared.
  Future<Result<Set<PublishPlatform>>> postedPlatformsOf(String goalId);

  /// Whether the goal [goalId] is still confirmed.
  Future<Result<bool>> goalStands(String goalId);

  /// The badges set for [teamIds].
  Future<Result<Map<String, StoredBadge>>> badges(Iterable<String> teamIds);

  /// Up to [limit] published posts with no metrics yet, published before
  /// [before].
  Future<Result<List<MetricsDue>>> metricsDue({
    required DateTime before,
    required int limit,
  });

  /// Keeps [metrics] for [postId], read at [at].
  Future<Result<void>> saveMetrics(
    String postId,
    PostMetrics metrics,
    DateTime at,
  );

  // The admin panel.

  /// The matches from [from] to [to] an admin may pick, picked ones marked.
  Future<Result<List<CoverageCandidate>>> candidates({
    required DateTime from,
    required DateTime to,
  });

  /// Starts covering [fixtureId] for [actorId]; again after a stop.
  /// Returns false when no visible match has that id.
  Future<Result<bool>> cover(String fixtureId, String actorId, DateTime at);

  /// Stops covering [fixtureId]; its goals and posts are kept.
  Future<Result<void>> stopCovering(String fixtureId, DateTime at);

  /// The latest [limit] posts, newest first.
  Future<Result<List<PostView>>> recentPosts({required int limit});

  /// One post, or null.
  Future<Result<PostView?>> post(String postId);

  /// Moves post [postId] from one of [from] to [to] at [at] (an admin's
  /// retry, cancel or "shared"); false when it was not in one of [from].
  Future<Result<bool>> movePost(
    String postId, {
    required Set<PostState> from,
    required PostState to,
    required DateTime at,
  });

  /// Every club badge set, with its club's name.
  Future<Result<List<StoredBadge>>> allBadges();

  /// Sets [teamId]'s badge for [actorId]; false when no club has that id.
  Future<Result<bool>> saveBadge(
    String teamId, {
    required String fill,
    required String? label,
    required String actorId,
  });
}
