import 'package:application/application.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeTargets implements AdminPushTargetReader {
  _FakeTargets(this._result);

  final Result<List<String>> _result;
  int calls = 0;

  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async {
    calls++;
    return _result;
  }
}

final class _FakeSender implements PushSender {
  final List<List<String>> tokens = <List<String>>[];
  final List<String> titles = <String>[];
  final List<String> bodies = <String>[];

  Result<List<String>> result = const Result.ok(<String>[]);

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    this.tokens.add(List<String>.from(tokens));
    titles.add(title);
    bodies.add(body);
    return result;
  }
}

void main() {
  group('NotifyNewUserRegistered', () {
    test('pushes only to the tokens returned for active admins', () async {
      final targets = _FakeTargets(
        const Result.ok(<String>['admin-a', 'admin-b']),
      );
      final sender = _FakeSender();

      final result = await NotifyNewUserRegistered(
        targets: targets,
        sender: sender,
      )();

      expect(result, isA<Ok<void>>());
      expect(targets.calls, 1);
      expect(sender.tokens.single, ['admin-a', 'admin-b']);
      expect(sender.titles.single, NotifyNewUserRegistered.title);
      expect(sender.bodies.single, NotifyNewUserRegistered.body);
    });

    test('does not call push when no active admin has a token', () async {
      final targets = _FakeTargets(const Result.ok(<String>[]));
      final sender = _FakeSender();

      final result = await NotifyNewUserRegistered(
        targets: targets,
        sender: sender,
      )();

      expect(result, isA<Ok<void>>());
      expect(sender.tokens, isEmpty);
    });

    test('propagates the target reader failure without pushing', () async {
      const failure = AppError.transient(
        'notification.admin_targets_failed',
        'boom',
      );
      final targets = _FakeTargets(const Result.err(failure));
      final sender = _FakeSender();

      final result = await NotifyNewUserRegistered(
        targets: targets,
        sender: sender,
      )();

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).error.code, failure.code);
      expect(sender.tokens, isEmpty);
    });
  });
}
