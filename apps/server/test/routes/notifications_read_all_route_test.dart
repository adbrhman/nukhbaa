import 'dart:io';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/notifications/read_all/index.dart' as route;
import 'competition_route_harness.dart';

/// `POST /notifications/read_all` through the real wiring over the in-memory
/// notification repository: the caller's unread rows are marked read with
/// the clock's instant, nobody else's are touched, and a repeat marks none.
void main() {
  final readAt = DateTime.utc(2026, 10, 6, 15);

  ({CompositionRoot root, InMemoryNotificationRepository notifications})
  rootFor() {
    final notifications = InMemoryNotificationRepository()
      ..seed(storedNotification(id: kNotificationId, recipientId: kUserId))
      ..seed(storedNotification(id: kNotificationId2, recipientId: kUserId))
      ..seed(
        storedNotification(id: kNotificationId3, recipientId: kMemberUserId),
      );
    final root = CompositionRoot.forTesting(
      markAllNotificationsRead: MarkAllNotificationsRead(
        notifications: notifications,
        clock: FixedClock(readAt),
      ),
    );
    return (root: root, notifications: notifications);
  }

  Future<Response> post(CompositionRoot root) => route.onRequest(
    wireContext(
      root: root,
      principal: userPrincipal(),
      method: HttpMethod.post,
    ),
  );

  test('marks the unread notifications of the caller read (200)', () async {
    final setup = rootFor();

    final response = await post(setup.root);

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['marked'], 2);
    final mine = setup.notifications.notifications.where(
      (n) => n.recipientId.value == kUserId,
    );
    expect(mine.every((n) => n.isRead && n.readAt == readAt), isTrue);
    final theirs = setup.notifications.notifications.singleWhere(
      (n) => n.recipientId.value == kMemberUserId,
    );
    expect(theirs.isRead, isFalse);
  });

  test('a repeat marks nothing (200 marked:0)', () async {
    final setup = rootFor();

    await post(setup.root);
    final again = await post(setup.root);

    expect(again.statusCode, HttpStatus.ok);
    expect((await decodeBody(again))['marked'], 0);
  });

  test('any other method is 405', () async {
    final response = await route.onRequest(
      wireContext(
        root: rootFor().root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
