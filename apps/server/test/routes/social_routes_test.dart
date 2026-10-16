import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/groups/[id]/feed/index.dart' as feed_route;
import 'competition_route_harness.dart';

/// Route tests for the Social (Tier-3) surface -- the activity-feed route
/// (`GET /groups/{id}/feed`; the round reactions route is gone, script 98),
/// exercised through the *real*
/// wiring (`context.read<Future<CompositionRoot>>()` → `root.<useCase>()`) over
/// the in-memory [InMemoryReactionRepository] + [InMemoryActivityFeedReader] +
/// [InMemoryGroupRepository] from [competition_route_harness]. This covers the
/// edge → use-case → domain → port path end-to-end, hermetically, mirroring
/// `group_routes_test.dart` / `ledger_routes_test.dart`.
///
/// It is NOT a substitute for the infrastructure adapters' own tests
/// (infrastructure package) or the use-cases' own tests (application package):
/// its job is the route's status mapping, DTO shaping, path-param handling, and
/// that each authorization gate (the member-only `group.not_a_member`
/// no-existence-oracle gate — Social decision #3) is honoured across the HTTP
/// boundary, plus the feed's `?limit=` clamp reaching the reader (decision #4).
void main() {
  // Builds a fresh root wiring the four Social use-cases over one shared trio of
  // in-memory repos, so a test can seed memberships/reactions/feed events and
  // observe the route behaviour end-to-end. The scripted id generator pins the
  // created reaction id; the clock pins reactedAt.
  ({
    CompositionRoot root,
    InMemoryReactionRepository reactions,
    InMemoryActivityFeedReader feed,
    InMemoryGroupRepository groups,
  })
  rootFor({List<String> ids = const [kReactionId, kReactionId2]}) {
    final reactions = InMemoryReactionRepository();
    final feed = InMemoryActivityFeedReader();
    final groups = InMemoryGroupRepository();
    final idGen = ScriptedIdGenerator(ids);
    final clock = FixedClock(DateTime.utc(2026, 7, 12, 12));
    final root = CompositionRoot.forTesting(
      reactToRound: ReactToRound(
        reactions: reactions,
        groups: groups,
        idGenerator: idGen,
        clock: clock,
      ),
      removeReaction: RemoveReaction(reactions: reactions, groups: groups),
      listRoundReactions: ListRoundReactions(
        reactions: reactions,
        groups: groups,
      ),
      getGroupActivityFeed: GetGroupActivityFeed(feed: feed, groups: groups),
    );
    return (root: root, reactions: reactions, feed: feed, groups: groups);
  }

  /// Seeds a membership for [userId] in the canonical group, so a
  /// member-gated route has a member to act as.
  void seedMember(
    InMemoryGroupRepository repo,
    String userId, {
    GroupRole role = GroupRole.member,
  }) {
    repo.seedMembership(
      storedMembership(
        id: kMemberMembershipId,
        userId: userId,
        role: role,
        joinedAt: DateTime.utc(2026, 7, 1),
      ),
    );
  }

  group('GET /groups/{id}/feed (activity feed)', () {
    test('a member reads the feed (200), newest-first', () async {
      final setup = rootFor();
      seedMember(setup.groups, kMemberUserId);
      setup.feed.seed(kGroupId, [
        ActivityEvent.memberJoined(
          groupId: const GroupId(kGroupId),
          userId: const UserId(kMemberUserId),
          occurredAt: DateTime.utc(2026, 7, 10),
        ),
        ActivityEvent.roundScored(
          groupId: const GroupId(kGroupId),
          roundId: const RoundId(kRoundId),
          occurredAt: DateTime.utc(2026, 7, 12),
        ),
      ]);

      final response = await feed_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.get,
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['group_id'], kGroupId);
      final events = body['events']! as List<Object?>;
      expect(events.length, 2);
      // Newest-first: the 2026-07-12 round_scored precedes the 2026-07-10 join.
      expect((events.first! as Map)['type'], 'round_scored');
      expect((events.first! as Map)['round_id'], kRoundId);
      expect((events.last! as Map)['type'], 'member_joined');
      expect((events.last! as Map)['user_id'], kMemberUserId);
    });

    test('an empty feed is a legitimate empty list (200)', () async {
      final setup = rootFor();
      seedMember(setup.groups, kMemberUserId);

      final response = await feed_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.get,
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['events'], isEmpty);
    });

    test('an in-range ?limit= reaches the reader as-is (clamp)', () async {
      final setup = rootFor();
      seedMember(setup.groups, kMemberUserId);

      final response = await feed_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.get,
          queryParameters: const {'limit': '10'},
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(setup.feed.lastLimit, 10);
    });

    test('an over-cap ?limit= is clamped to maxLimit at the reader', () async {
      final setup = rootFor();
      seedMember(setup.groups, kMemberUserId);

      final response = await feed_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.get,
          queryParameters: const {'limit': '9999'},
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(setup.feed.lastLimit, GetGroupActivityFeed.maxLimit);
    });

    test(
      'a non-integer ?limit= falls back to the default at the reader',
      () async {
        final setup = rootFor();
        seedMember(setup.groups, kMemberUserId);

        final response = await feed_route.onRequest(
          wireContext(
            root: setup.root,
            principal: memberPrincipal(),
            method: HttpMethod.get,
            queryParameters: const {'limit': 'abc'},
          ),
          kGroupId,
        );

        expect(response.statusCode, HttpStatus.ok);
        expect(setup.feed.lastLimit, GetGroupActivityFeed.defaultLimit);
      },
    );

    test('a missing ?limit= falls back to the default at the reader', () async {
      final setup = rootFor();
      seedMember(setup.groups, kMemberUserId);

      final response = await feed_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.get,
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(setup.feed.lastLimit, GetGroupActivityFeed.defaultLimit);
    });

    test(
      'a non-member is refused 401 group.not_a_member (no oracle)',
      () async {
        final setup = rootFor();

        final response = await feed_route.onRequest(
          wireContext(
            root: setup.root,
            principal: nonMemberPrincipal(),
            method: HttpMethod.get,
          ),
          kGroupId,
        );

        expect(response.statusCode, HttpStatus.unauthorized);
        final body = await decodeBody(response);
        expect(body['code'], 'group.not_a_member');
      },
    );

    test('a transient feed failure is 503 (Tier-3 confined)', () async {
      final setup = rootFor();
      seedMember(setup.groups, kMemberUserId);
      setup.feed.failNextWith(
        const AppError.transient('social.row_corrupt', 'boom'),
      );

      final response = await feed_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.get,
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });

    test('feed route rejects a non-GET method with 405', () async {
      final setup = rootFor();

      final response = await feed_route.onRequest(
        wireContext(
          root: setup.root,
          principal: memberPrincipal(),
          method: HttpMethod.post,
        ),
        kGroupId,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
