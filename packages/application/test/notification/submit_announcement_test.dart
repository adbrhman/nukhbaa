import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _owner = uuidA;
const _admin = uuidB;
const _player1 = uuidC;
const _player2 = uuidD;
const _request = '55555555-5555-4555-8555-555555555555';

/// [AnnouncementRepository] over two lists: the active players and what
/// was published.
final class _Announcements implements AnnouncementRepository {
  final List<Announcement> saved = [];

  @override
  Future<Result<void>> save(Announcement announcement) async {
    if (!saved.any((a) => a.id == announcement.id)) saved.add(announcement);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<Announcement>>> findByIds(
    List<AnnouncementId> ids,
  ) async => Result.ok([
    for (final a in saved)
      if (ids.contains(a.id)) a,
  ]);

  @override
  Future<Result<List<AnnouncementRecipient>>> audience() async =>
      const Result.ok([
        AnnouncementRecipient(userId: UserId(_player1), tokens: []),
        AnnouncementRecipient(userId: UserId(_player2), tokens: []),
      ]);
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
  Future<Result<List<QueuedPush>>> claimDue({
    required DateTime now,
    required int limit,
  }) => throw StateError('never claims');

  @override
  Future<Result<void>> forgetTokens(List<String> tokens) =>
      throw StateError('never forgets');
}

/// The owner seats: [_owner] alone; [told] what they were told.
final class _Seats implements OwnerNotices {
  bool fails = false;
  final List<String> told = [];

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<bool>> isOwner(UserId user) async => fails
      ? const Result.err(AppError.transient('db.down', 'down'))
      : Result.ok(user == const UserId(_owner));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async {
    told.add('$title|$body');
    return const Result.ok(null);
  }
}

/// `notification.announcement_requests` in memory.
final class _Requests implements AnnouncementRequestStore {
  final Map<String, AnnouncementRequest> rows = {};

  @override
  Future<Result<(AnnouncementRequest, bool)>> hold({
    required AnnouncementId id,
    required UserId author,
    required String title,
    required String body,
  }) async {
    final AnnouncementRequest? held = rows[id.value];
    if (held != null) return Result.ok((held, false));
    final AnnouncementRequest made = AnnouncementRequest(
      id: id,
      authorId: author,
      authorName: 'سليمان',
      title: title,
      body: body,
      status: AnnouncementRequestStatus.pending,
      createdAt: DateTime.utc(2026, 11, 20, 9),
    );
    rows[id.value] = made;
    return Result.ok((made, true));
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
    rows[id.value] = AnnouncementRequest(
      id: r.id,
      authorId: r.authorId,
      authorName: r.authorName,
      title: r.title,
      body: r.body,
      status: to,
      createdAt: r.createdAt,
      decidedAt: DateTime.utc(2026, 11, 20, 10),
      recipients: recipients,
    );
    return const Result.ok(true);
  }
}

// NK290_15
/// Script 290: an owner seat's announcement goes out at once; any other
/// admin's waits for an owner seat, who publishes it as written or
/// rejects it.
void main() {
  late _Announcements announcements;
  late InMemoryNotificationRepository inboxes;
  late _Seats seats;
  late _Requests requests;
  late SubmitAnnouncement submit;
  late OwnerAnnouncementReview review;

  final AuthenticatedUser owner = principalUser(
    userId: _owner,
    role: PlatformRole.admin,
  );
  final AuthenticatedUser admin = principalUser(
    userId: _admin,
    role: PlatformRole.admin,
  );

  setUp(() {
    announcements = _Announcements();
    inboxes = InMemoryNotificationRepository();
    seats = _Seats();
    requests = _Requests();
    final PublishAnnouncement publish = PublishAnnouncement(
      announcements: announcements,
      create: CreateNotification(
        notifications: inboxes,
        idGenerator: FakeIdGenerator([
          '66666666-6666-4666-8666-666666666661',
          '66666666-6666-4666-8666-666666666662',
          '66666666-6666-4666-8666-666666666663',
        ]),
        clock: FakeClock(),
      ),
      sender: _Sender(),
      idGenerator: FakeIdGenerator([_request]),
      clock: FakeClock(),
      queue: _Queue(),
    );
    submit = SubmitAnnouncement(
      publish: publish,
      requests: requests,
      owners: seats,
      idGenerator: FakeIdGenerator([_request]),
      clock: FakeClock(),
    );
    review = OwnerAnnouncementReview(
      requests: requests,
      publish: publish,
      owners: seats,
    );
  });

  int reached() => inboxes.countFor(_player1) + inboxes.countFor(_player2);

  test('an owner seat publishes at once', () async {
    final result = await submit(principal: owner, title: 'تنبيه', body: 'نص');

    final AnnouncementSubmitted out =
        (result as Ok<AnnouncementSubmitted>).value;
    expect(out.status, AnnouncementRequestStatus.published);
    expect(out.recipients, 2);
    expect(requests.rows, isEmpty);
    expect(seats.told, isEmpty);
  });

  test('another admin\'s waits, and the owners are told once', () async {
    final first = await submit(
      principal: admin,
      title: ' تنبيه ',
      body: 'نص',
      requestId: _request,
    );
    final again = await submit(
      principal: admin,
      title: 'تنبيه',
      body: 'نص',
      requestId: _request,
    );

    expect(
      (first as Ok<AnnouncementSubmitted>).value.status,
      AnnouncementRequestStatus.pending,
    );
    expect((again as Ok<AnnouncementSubmitted>).value.recipients, 0);
    expect(requests.rows[_request]!.title, 'تنبيه');
    expect(reached(), 0, reason: 'nobody receives it yet');
    expect(seats.told, hasLength(1));
    expect(seats.told.single, contains('سليمان'));
  });

  test('a failed seat lookup holds it, never publishes it', () async {
    seats.fails = true;

    final result = await submit(principal: owner, title: 'تنبيه', body: 'نص');

    expect(
      (result as Ok<AnnouncementSubmitted>).value.status,
      AnnouncementRequestStatus.pending,
    );
    expect(reached(), 0);
  });

  test('blank text is refused before it is held', () async {
    final result = await submit(principal: admin, title: 'تنبيه', body: '  ');

    expect(
      (result as Err<AnnouncementSubmitted>).error.code,
      'notification.announcement_body_empty',
    );
    expect(requests.rows, isEmpty);
  });

  test('an owner publishes it as the admin wrote it, once', () async {
    await submit(
      principal: admin,
      title: 'تنبيه',
      body: 'نص',
      requestId: _request,
    );

    final sent = await review.publish(principal: owner, requestId: _request);
    final twice = await review.publish(principal: owner, requestId: _request);

    expect((sent as Ok<int>).value, 2);
    expect(reached(), 2);
    expect(announcements.saved.single.authorId, const UserId(_admin));
    expect(
      requests.rows[_request]!.status,
      AnnouncementRequestStatus.published,
    );
    expect(requests.rows[_request]!.recipients, 2);
    expect((twice as Err<int>).error.code, 'announcement.already_decided');
    expect(reached(), 2);
  });

  test('a rejected one reaches nobody, and the admin reads it', () async {
    await submit(
      principal: admin,
      title: 'تنبيه',
      body: 'نص',
      requestId: _request,
    );

    final rejected = await review.reject(principal: owner, requestId: _request);
    final mine = await submit.mine(principal: admin);

    expect(rejected, isA<Ok<void>>());
    expect(reached(), 0);
    expect(
      (mine as Ok<List<AnnouncementRequest>>).value.single.status,
      AnnouncementRequestStatus.rejected,
    );
    expect(
      (await review.publish(principal: owner, requestId: _request) as Err<int>)
          .error
          .code,
      'announcement.already_decided',
    );
  });

  test('only an owner seat reviews', () async {
    await submit(
      principal: admin,
      title: 'تنبيه',
      body: 'نص',
      requestId: _request,
    );

    final listed = await review.list(principal: admin);
    final sent = await review.publish(principal: admin, requestId: _request);
    final unknown = await review.reject(
      principal: owner,
      requestId: '77777777-7777-4777-8777-777777777777',
    );

    expect(
      (listed as Err<List<AnnouncementRequest>>).error.code,
      'admin.owner_only',
    );
    expect((sent as Err<int>).error.code, 'admin.owner_only');
    expect((unknown as Err<void>).error.code, 'announcement.request_not_found');
    expect(reached(), 0);
  });
}
