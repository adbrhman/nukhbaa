import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/publisher/ports/publisher_outlets.dart';
import 'package:application/src/publisher/ports/publisher_store.dart';
import 'package:application/src/publisher/publisher_tick.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What the admin panel's «النشر الرياضي الذكي» shows at once.
final class PublisherOverview {
  /// Creates the overview.
  const PublisherOverview({
    required this.mode,
    required this.settings,
    required this.candidates,
    required this.posts,
    required this.badges,
    required this.linked,
  });

  /// Whether the server sends, only prepares, or does nothing.
  final PublisherMode mode;

  /// Each platform's setting.
  final Map<PublishPlatform, PlatformIntensity> settings;

  /// The matches of the coming days, picked ones marked.
  final List<CoverageCandidate> candidates;

  /// The latest posts.
  final List<PostView> posts;

  /// The club colours set.
  final List<StoredBadge> badges;

  /// The platforms whose account the server holds a token for.
  final Set<PublishPlatform> linked;
}

/// What an admin can do to a post.
enum PostAction {
  /// Back in the queue now (a failed, uncertain, skipped or cancelled post,
  /// or a dry-run post once the server sends).
  retry,

  /// Never sent.
  cancel,

  /// An X post the admin shared by hand.
  shared,
}

/// The admin side of the sports publisher (migration 0200). Admin only;
/// every call checks the caller first. Never throws.
final class AdminPublisher {
  /// Creates the use-case.
  const AdminPublisher({
    required PublisherStore store,
    required PublisherMode mode,
    required Map<PublishPlatform, PlatformPoster> posters,
    required Clock clock,
    PublisherCardHost? host,
  }) : _store = store,
       _mode = mode,
       _posters = posters,
       _clock = clock,
       _host = host;

  final PublisherStore _store;
  final PublisherMode _mode;
  final Map<PublishPlatform, PlatformPoster> _posters;
  final Clock _clock;
  final PublisherCardHost? _host;

  /// How far ahead the panel lists matches to pick.
  static const Duration ahead = Duration(days: 3);

  /// How far back it still lists them (a match in play can be picked).
  static const Duration behind = Duration(hours: 3);

  /// The panel's overview.
  Future<Result<PublisherOverview>> overview({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final now = _clock.nowUtc();
    final settings = await _store.settings();
    if (settings is Err<Map<PublishPlatform, PlatformIntensity>>) {
      return Result.err(settings.error);
    }
    final candidates = await _store.candidates(
      from: now.subtract(behind),
      to: now.add(ahead),
    );
    if (candidates is Err<List<CoverageCandidate>>) {
      return Result.err(candidates.error);
    }
    final posts = await _store.recentPosts(limit: 60);
    if (posts is Err<List<PostView>>) {
      return Result.err(posts.error);
    }
    final badges = await _store.allBadges();
    if (badges is Err<List<StoredBadge>>) {
      return Result.err(badges.error);
    }
    return Result.ok(
      PublisherOverview(
        mode: _mode,
        settings:
            (settings as Ok<Map<PublishPlatform, PlatformIntensity>>).value,
        candidates: (candidates as Ok<List<CoverageCandidate>>).value,
        posts: (posts as Ok<List<PostView>>).value,
        badges: (badges as Ok<List<StoredBadge>>).value,
        linked: _posters.keys.toSet(),
      ),
    );
  }

  /// Sets one platform's [intensity].
  Future<Result<PlatformIntensity>> setIntensity({
    required AuthenticatedUser principal,
    required PlatformIntensity intensity,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final field = intensity.outOfBounds();
    if (field != null) {
      return Result.err(
        AppError.validation(
          'publisher.setting_out_of_bounds',
          'قيمة خارج الحدود: $field',
        ),
      );
    }
    final saved = await _store.saveSetting(intensity, principal.userId.value);
    if (saved is Err<void>) return Result.err(saved.error);
    return Result.ok(intensity);
  }

  /// Starts or stops covering [fixtureId].
  Future<Result<void>> setCovered({
    required AuthenticatedUser principal,
    required String fixtureId,
    required bool covered,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    if (!_uuid.hasMatch(fixtureId)) {
      return const Result.err(
        AppError.validation(
          'publisher.fixture_invalid',
          'معرّف مباراة غير صالح.',
        ),
      );
    }
    final now = _clock.nowUtc();
    if (!covered) {
      return _store.stopCovering(fixtureId, now);
    }
    final added = await _store.cover(fixtureId, principal.userId.value, now);
    if (added is Err<bool>) return Result.err(added.error);
    if (!(added as Ok<bool>).value) {
      return const Result.err(
        AppError.invariant(
          'publisher.fixture_not_found',
          'المباراة غير موجودة.',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// Sets a club's colour and label.
  Future<Result<StoredBadge>> setBadge({
    required AuthenticatedUser principal,
    required String teamId,
    required String fill,
    required String? label,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    if (!_uuid.hasMatch(teamId)) {
      return const Result.err(
        AppError.validation('publisher.team_invalid', 'معرّف نادٍ غير صالح.'),
      );
    }
    if (!ClubBadge.isColour(fill)) {
      return const Result.err(
        AppError.validation(
          'publisher.colour_invalid',
          'اللون يُكتب هكذا: #1978D1',
        ),
      );
    }
    final words = label?.trim();
    if (words != null && (words.isEmpty || words.length > 24)) {
      return const Result.err(
        AppError.validation(
          'publisher.label_invalid',
          'الاسم على الشارة من حرف إلى 24 حرفاً.',
        ),
      );
    }
    final saved = await _store.saveBadge(
      teamId,
      fill: fill.toUpperCase(),
      label: words,
      actorId: principal.userId.value,
    );
    if (saved is Err<bool>) return Result.err(saved.error);
    if (!(saved as Ok<bool>).value) {
      return const Result.err(
        AppError.invariant('publisher.team_not_found', 'النادي غير موجود.'),
      );
    }
    return Result.ok(
      StoredBadge(
        teamId: teamId,
        teamName: '',
        fill: fill.toUpperCase(),
        label: words,
      ),
    );
  }

  /// Applies [action] to post [postId].
  Future<Result<void>> act({
    required AuthenticatedUser principal,
    required String postId,
    required PostAction action,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    if (!_uuid.hasMatch(postId)) {
      return const Result.err(
        AppError.validation('publisher.post_invalid', 'معرّف منشور غير صالح.'),
      );
    }
    final (from, to) = switch (action) {
      PostAction.retry => (
        <PostState>{
          PostState.failed,
          PostState.uncertain,
          PostState.skipped,
          PostState.cancelled,
          PostState.dryRun,
        },
        PostState.queued,
      ),
      PostAction.cancel => (
        <PostState>{PostState.queued, PostState.readyToShare},
        PostState.cancelled,
      ),
      PostAction.shared => (
        <PostState>{PostState.readyToShare},
        PostState.shared,
      ),
    };
    final moved = await _store.movePost(
      postId,
      from: from,
      to: to,
      at: _clock.nowUtc(),
    );
    if (moved is Err<bool>) return Result.err(moved.error);
    if (!(moved as Ok<bool>).value) {
      return const Result.err(
        AppError.invariant(
          'publisher.post_state',
          'لا يمكن تنفيذ هذا على المنشور في حالته الآن.',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// The picture of post [postId] (to preview it, or to share it on X).
  Future<Result<List<int>>> card({
    required AuthenticatedUser principal,
    required String postId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    if (!_uuid.hasMatch(postId)) {
      return const Result.err(
        AppError.validation('publisher.post_invalid', 'معرّف منشور غير صالح.'),
      );
    }
    final read = await _store.post(postId);
    if (read is Err<PostView?>) return Result.err(read.error);
    final path = (read as Ok<PostView?>).value?.cardPath;
    final host = _host;
    if (path == null || host == null) {
      return const Result.err(
        AppError.invariant('publisher.no_card', 'لا صورة لهذا المنشور.'),
      );
    }
    return host.get(path);
  }

  /// Asks each linked platform who its token belongs to.
  Future<Result<Map<PublishPlatform, Result<String>>>> checkAccounts({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final checks = <PublishPlatform, Result<String>>{};
    for (final entry in _posters.entries) {
      checks[entry.key] = await entry.value.verify();
    }
    return Result.ok(checks);
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
