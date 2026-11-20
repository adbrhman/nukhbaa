import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/announcements/index.dart' as publish_route;
// ignore: always_use_package_imports
import '../../routes/admin/announcements/mine.dart' as mine_route;
// ignore: always_use_package_imports
import '../../routes/owner/announcements/[id]/index.dart' as decide_route;
// ignore: always_use_package_imports
import '../../routes/owner/announcements/index.dart' as review_route;
import 'competition_route_harness.dart';

const _admin = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';
const _player = '0c0c0c0c-0c0c-4c0c-8c0c-0c0c0c0c0c0c';
const _request = '0d0d0d0d-0d0d-4d0d-8d0d-0d0d0d0d0d0d';

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 11, 20, 9);
}

final class _Ids implements IdGenerator {
  int _n = 0;

  @override
  String newUuid() =>
      '0e0e0e0e-0e0e-4e0e-8e0e-${(++_n).toString().padLeft(12, '0')}';
}

/// The harness admin [kAdminId] holds the owner seat.
final class _Seats implements OwnerNotices {
  final List<String> told = [];

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(kAdminId));

  @override
  Future<Result<bool>> isOwner(UserId user) async =>
      Result.ok(user == const UserId(kAdminId));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async {
    told.add(title);
    return const Result.ok(null);
  }
}

final class _Announcements implements AnnouncementRepository {
  final List<Announcement> saved = [];

  @override
  Future<Result<void>> save(Announcement announcement) async {
    saved.add(announcement);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<Announcement>>> findByIds(
    List<AnnouncementId> ids,
  ) async => const Result.ok([]);

  @override
  Future<Result<List<AnnouncementRecipient>>> audience() async =>
      const Result.ok([
        AnnouncementRecipient(userId: UserId(_player), tokens: []),
      ]);
}

final class _Inboxes implements NotificationRepository {
  final Set<String> keys = {};

  @override
  Future<Result<bool>> createIfAbsent(Notification notification) async =>
      Result.ok(
        keys.add(
          '${notification.recipientId.value}|${notification.subject.dedupeRef}',
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not used: ${invocation.memberName}');
}

final class _Sender implements PushSender {
  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async => const Result.ok(<String>[]);
}

final class _Queue implements NotificationQueue {
  @override
  Future<Result<void>> enqueue(List<PushToQueue> pushes) async =>
      const Result.ok(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not used: ${invocation.memberName}');
}

final class _Requests implements AnnouncementRequestStore {
  final Map<String, AnnouncementRequest> rows = {};

  AnnouncementRequest _with(
    AnnouncementRequest r,
    AnnouncementRequestStatus status,
    int? recipients,
  ) => AnnouncementRequest(
    id: r.id,
    authorId: r.authorId,
    authorName: r.authorName,
    title: r.title,
    body: r.body,
    status: status,
    createdAt: r.createdAt,
    decidedAt: DateTime.utc(2026, 11, 20, 10),
    recipients: recipients,
  );

  @override
  Future<Result<(AnnouncementRequest, bool)>> hold({
    required AnnouncementId id,
    required UserId author,
    required String title,
    required String body,
  }) async {
    final AnnouncementRequest? held = rows[id.value];
    if (held != null) return Result.ok((held, false));
    return Result.ok((
      rows[id.value] = AnnouncementRequest(
        id: id,
        authorId: author,
        authorName: 'سليمان',
        title: title,
        body: body,
        status: AnnouncementRequestStatus.pending,
        createdAt: DateTime.utc(2026, 11, 20, 9),
      ),
      true,
    ));
  }

  @override
  Future<Result<AnnouncementRequest?>> byId(AnnouncementId id) async =>
      Result.ok(rows[id.value]);

  @override
  Future<Result<List<AnnouncementRequest>>> latest({int limit = 50}) async =>
      Result.ok(rows.values.toList());

  @override
  Future<Result<List<AnnouncementRequest>>> byAuthor(
    UserId author, {
    int limit = 20,
  }) async => Result.ok([
    for (final r in rows.values)
      if (r.authorId == author) r,
  ]);

  @override
  Future<Result<bool>> decide({
    required AnnouncementId id,
    required AnnouncementRequestStatus to,
    required UserId by,
    int? recipients,
  }) async {
    final AnnouncementRequest? r = rows[id.value];
    if (r == null || r.status != AnnouncementRequestStatus.pending) {
      return const Result.ok(false);
    }
    rows[id.value] = _with(r, to, recipients);
    return const Result.ok(true);
  }
}

AuthenticatedUser _as(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.admin);

// NK290_17
/// Script 290: the announcement an admin sends, held for an owner seat,
/// and the owners' review, through the routes and the real use-cases.
void main() {
  late _Requests requests;
  late _Announcements announcements;
  late _Seats seats;
  late CompositionRoot root;

  setUp(() {
    requests = _Requests();
    announcements = _Announcements();
    seats = _Seats();
    final PublishAnnouncement publish = PublishAnnouncement(
      announcements: announcements,
      create: CreateNotification(
        notifications: _Inboxes(),
        idGenerator: _Ids(),
        clock: _Clock(),
      ),
      sender: _Sender(),
      idGenerator: _Ids(),
      clock: _Clock(),
      queue: _Queue(),
    );
    root = CompositionRoot.forTesting(
      submitAnnouncement: SubmitAnnouncement(
        publish: publish,
        requests: requests,
        owners: seats,
        idGenerator: _Ids(),
        clock: _Clock(),
      ),
      ownerAnnouncementReview: OwnerAnnouncementReview(
        requests: requests,
        publish: publish,
        owners: seats,
      ),
    );
  });

  Future<Map<String, Object?>> send(String who) async => decodeBody(
    await publish_route.onRequest(
      wireContext(
        root: root,
        principal: _as(who),
        body: const {'title': 'تنبيه', 'body': 'نص', 'request_id': _request},
      ),
    ),
  );

  Future<Map<String, Object?>> decide(String action) async => decodeBody(
    await decide_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        body: {'action': action},
      ),
      _request,
    ),
  );

  test('an admin\'s announcement waits, and he reads it pending', () async {
    final sent = await send(_admin);

    expect(sent['status'], 'pending');
    expect(sent['recipients'], 0);
    expect(announcements.saved, isEmpty);
    expect(seats.told, ['إعلان ينتظر مراجعتك']);

    final mine = await decodeBody(
      await mine_route.onRequest(
        wireContext(root: root, principal: _as(_admin), method: HttpMethod.get),
      ),
    );
    final line =
        (mine['requests']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(line['status'], 'pending');
    expect(line['title'], 'تنبيه');
  });

  test('an owner seat\'s announcement goes out at once', () async {
    final sent = await send(kAdminId);

    expect(sent['status'], 'published');
    expect(sent['recipients'], 1);
    expect(requests.rows, isEmpty);
  });

  test('the owner lists it and publishes it once', () async {
    await send(_admin);

    final listed = await decodeBody(
      await review_route.onRequest(
        wireContext(
          root: root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      ),
    );
    final published = await decide('publish');
    final again = await decide('publish');

    expect((listed['requests']! as List<Object?>), hasLength(1));
    expect(published, {'status': 'published', 'recipients': 1});
    expect(announcements.saved.single.authorId, const UserId(_admin));
    expect(again['code'], 'announcement.already_decided');
  });

  test('the owner rejects it; nobody receives it', () async {
    await send(_admin);

    expect(await decide('reject'), {'status': 'rejected'});
    expect(announcements.saved, isEmpty);
    expect(requests.rows[_request]!.status, AnnouncementRequestStatus.rejected);
    expect((await decide('hide'))['code'], 'announcement.action_invalid');
  });

  test('an admin without a seat cannot review', () async {
    await send(_admin);

    final response = await decide_route.onRequest(
      wireContext(
        root: root,
        principal: _as(_admin),
        body: const {'action': 'publish'},
      ),
      _request,
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect(announcements.saved, isEmpty);
  });
}
