import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';

UserId _id(String raw) => (UserId.tryParse(raw) as Ok<UserId>).value;

QueuedPush _push(String id, String user, List<String> tokens) => QueuedPush(
  id: id,
  userId: _id(user),
  title: 'title $id',
  body: 'body $id',
  tokens: tokens,
);

/// Answers the scripted batches in order, then empty batches, and records
/// every claim.
final class _FakeQueue implements NotificationQueue {
  _FakeQueue(this.batches, {this.failWith});

  final List<List<QueuedPush>> batches;
  final AppError? failWith;
  final List<(DateTime, int)> claims = [];

  @override
  Future<Result<List<QueuedPush>>> claimDue({
    required DateTime now,
    required int limit,
  }) async {
    claims.add((now, limit));
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    final index = claims.length - 1;
    return Result.ok(index < batches.length ? batches[index] : const []);
  }
}

final class _FakeSender implements PushSender {
  _FakeSender({this.failFor = const {}});

  final Set<String> failFor;
  final List<(List<String>, String, String)> sent = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
  }) async {
    if (tokens.any(failFor.contains)) {
      return const Result.err(AppError.transient('fcm.down', 'down'));
    }
    sent.add((tokens, title, body));
    return const Result.ok(<String>[]);
  }
}

void main() {
  group('FlushNotificationQueue', () {
    final now = DateTime.utc(2026, 9, 24, 5);

    test('delivers each claimed push to its own devices', () async {
      final queue = _FakeQueue([
        [
          _push('p1', _userA, ['t1', 't2']),
          _push('p2', _userB, ['t3']),
        ],
      ]);
      final sender = _FakeSender();

      final result = await FlushNotificationQueue(queue: queue, sender: sender)(
        now: now,
      );

      expect((result as Ok<int>).value, 2);
      expect(
        [
          for (final (tokens, title, body) in sender.sent)
            '$tokens|$title|$body',
        ],
        ['[t1, t2]|title p1|body p1', '[t3]|title p2|body p2'],
      );
      expect(queue.claims, [(now, FlushNotificationQueue.batchSize)]);
    });

    test('an empty queue claims once and sends nothing', () async {
      final queue = _FakeQueue([]);
      final sender = _FakeSender();

      final result = await FlushNotificationQueue(queue: queue, sender: sender)(
        now: now,
      );

      expect((result as Ok<int>).value, 0);
      expect(queue.claims, hasLength(1));
      expect(sender.sent, isEmpty);
    });

    test('a user with no device left is claimed and dropped', () async {
      final queue = _FakeQueue([
        [
          _push('p1', _userA, const []),
          _push('p2', _userB, ['t3']),
        ],
      ]);
      final sender = _FakeSender();

      final result = await FlushNotificationQueue(queue: queue, sender: sender)(
        now: now,
      );

      expect((result as Ok<int>).value, 1);
      expect(sender.sent.single.$1, ['t3']);
    });

    test('a failed send is not counted and not retried', () async {
      final queue = _FakeQueue([
        [
          _push('p1', _userA, ['bad']),
          _push('p2', _userB, ['t3']),
        ],
      ]);
      final sender = _FakeSender(failFor: {'bad'});

      final result = await FlushNotificationQueue(queue: queue, sender: sender)(
        now: now,
      );

      expect((result as Ok<int>).value, 1);
      expect(queue.claims, hasLength(1));
    });

    test('a full batch is followed by another claim', () async {
      final full = [
        for (var i = 0; i < FlushNotificationQueue.batchSize; i++)
          _push('p$i', _userA, ['t$i']),
      ];
      final queue = _FakeQueue([
        full,
        [
          _push('last', _userB, ['t-last']),
        ],
      ]);
      final sender = _FakeSender();

      final result = await FlushNotificationQueue(queue: queue, sender: sender)(
        now: now,
      );

      expect((result as Ok<int>).value, FlushNotificationQueue.batchSize + 1);
      expect(queue.claims, hasLength(2));
    });

    test('a failed claim surfaces and sends nothing', () async {
      final queue = _FakeQueue(
        [],
        failWith: const AppError.transient('db.down', 'down'),
      );
      final sender = _FakeSender();

      final result = await FlushNotificationQueue(queue: queue, sender: sender)(
        now: now,
      );

      expect((result as Err<int>).error.code, 'db.down');
      expect(sender.sent, isEmpty);
    });
  });
}
