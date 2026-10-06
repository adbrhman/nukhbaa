import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/ports/notification_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: mark every one of the caller's OWN unread notifications
/// read -- the inbox was opened, so the bell's count starts again from zero
/// and shows only what arrives after.
///
/// **Recipient-only (decision #4):** the recipient is the verified principal,
/// never a body or path, so no other inbox can be touched.
///
/// **Idempotent:** a row already read keeps its original read timestamp; a
/// repeat marks nothing and answers zero.
///
/// The read timestamp is stamped from the injected [Clock] (UTC).
///
/// Never throws; returns a typed [Result] carrying how many notifications
/// went from unread to read.
final class MarkAllNotificationsRead {
  /// Creates the use-case over its collaborators.
  const MarkAllNotificationsRead({
    required NotificationRepository notifications,
    required Clock clock,
  }) : _notifications = notifications,
       _clock = clock;

  final NotificationRepository _notifications;
  final Clock _clock;

  /// Marks every unread notification of [principal] read.
  Future<Result<int>> call({required AuthenticatedUser principal}) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _notifications.markAllRead(principal.userId, _clock.nowUtc());
  }
}
