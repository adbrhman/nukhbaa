import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  final readAt = DateTime.utc(2026, 10, 6, 15);
  final earlier = DateTime.utc(2026, 10, 1, 9);

  ({InMemoryNotificationRepository repo, MarkAllNotificationsRead useCase})
  setup() {
    final repo = InMemoryNotificationRepository()
      ..seed(storedRoundScored(id: uuidA, recipientId: uuidD, roundId: uuidC))
      ..seed(storedRoundScored(id: uuidB, recipientId: uuidD, roundId: uuidC))
      ..seed(
        storedRoundScored(
          id: uuidC,
          recipientId: uuidD,
          roundId: uuidC,
          readAt: earlier,
        ),
      )
      // Someone else's unread notification: never touched.
      ..seed(storedRoundScored(id: uuidD, recipientId: uuidA, roundId: uuidC));
    return (
      repo: repo,
      useCase: MarkAllNotificationsRead(
        notifications: repo,
        clock: FakeClock(readAt),
      ),
    );
  }

  test('marks every unread notification of the caller read', () async {
    final s = setup();

    final result = await s.useCase(principal: principalUser(userId: uuidD));

    expect((result as Ok<int>).value, 2);
    expect((await s.repo.unreadCount(const UserId(uuidD)) as Ok<int>).value, 0);
  });

  test('never touches another recipient', () async {
    final s = setup();

    await s.useCase(principal: principalUser(userId: uuidD));

    expect((await s.repo.unreadCount(const UserId(uuidA)) as Ok<int>).value, 1);
  });

  test('a repeat marks nothing and keeps the original timestamps', () async {
    final s = setup();

    await s.useCase(principal: principalUser(userId: uuidD));
    final again = await s.useCase(principal: principalUser(userId: uuidD));
    final already = await s.repo.findForRecipient(
      const NotificationId(uuidC),
      const UserId(uuidD),
    );

    expect((again as Ok<int>).value, 0);
    expect((already as Ok<Notification?>).value!.readAt, earlier);
  });

  test('a storage failure is returned, not thrown', () async {
    final s = setup();
    s.repo.failNextWith(const AppError.transient('db.down', 'down'));

    final result = await s.useCase(principal: principalUser(userId: uuidD));

    expect((result as Err<int>).error.code, 'db.down');
  });
}
