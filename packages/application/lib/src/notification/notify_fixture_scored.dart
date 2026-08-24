import 'package:application/src/notification/create_notification.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class NotifyFixtureScored {
  const NotifyFixtureScored({required CreateNotification create})
    : _create = create;

  final CreateNotification _create;

  Future<Result<bool>> call({
    required UserId recipientId,
    required String fixtureId,
  }) async {
    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    return _create(
      recipientId: recipientId,
      kind: NotificationKind.fixtureScored,
      subject: NotificationSubject.fixtureScored(fixture: fixture),
    );
  }
}
