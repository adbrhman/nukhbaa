import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the caller's OWN Notifications inbox (Tier-3, recipient-
/// only surface of `apps/server`).
///
/// Wraps exactly the three ratified routes, verbatim:
///   * `GET /notifications` -> [NotificationListDto]
///     (`routes/notifications/index.dart`).
///   * `GET /notifications/unread_count` -> the recipient's whole-inbox
///     unread count (`routes/notifications/unread_count/index.dart`).
///   * `POST /notifications/{id}/read` -> whether this call transitioned the
///     notification unread->read (`routes/notifications/[id]/read/index.dart`).
///
/// **Recipient-only (Notifications decision #4):** every gate lives inside the
/// server use-cases — the recipient is bound from the verified token, never a
/// path or body value this client supplies. A foreign/unknown notification id
/// is refused identically as `401 notification.not_found` (no existence
/// oracle).
///
/// The whole `/notifications` subtree is already behind `bearerAuth`; an
/// unauthenticated call is refused there with `401`. Every method returns a
/// typed [Result] and never throws.
final class NotificationsApi {
  /// Creates the Notifications client over the shared [ApiTransport].
  const NotificationsApi(this._transport);

  final ApiTransport _transport;

  /// `GET /notifications` — the caller's own inbox, newest first, plus their
  /// whole-inbox unread count. [limit] is an optional page-size hint; the
  /// server clamps an untrusted value rather than rejecting it.
  Future<Result<NotificationListDto>> listMine({int? limit}) {
    return _transport.getObject<NotificationListDto>(
      '/notifications',
      query: limit == null ? null : {'limit': '$limit'},
      parse: NotificationListDto.fromJson,
    );
  }

  /// `GET /notifications/unread_count` — the caller's own unread count
  /// (always `>= 0`; zero is legitimate).
  Future<Result<int>> unreadCount() {
    return _transport.getObject<int>(
      '/notifications/unread_count',
      parse: (json) => json['unread_count']! as int,
    );
  }

  /// `POST /notifications/{notificationId}/read` — idempotently marks the
  /// caller's own notification read. Returns `true` when this call performed
  /// the unread->read transition, `false` when it was already read (both are
  /// a success).
  Future<Result<bool>> markRead(String notificationId) {
    return _transport.postObject<bool>(
      '/notifications/$notificationId/read',
      body: const {},
      parse: (json) => json['read']! as bool,
    );
  }
}
