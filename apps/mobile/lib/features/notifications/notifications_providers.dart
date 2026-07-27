/// The Notifications **view** state and mark-read **command** — mirrors the
/// split used across the app: read-only `FutureProvider`s
/// (`myNotificationsProvider`, `unreadCountProvider`) plus one notifier that
/// owns the single client-safe Tier-3 mutation (`MarkNotificationRead`).
///
/// Recipient-only (Notifications decision #4): every gate lives server-side,
/// bound to the verified token — this file never supplies a recipient id.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'notifications_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// `GET /notifications` — the caller's own inbox, newest first, plus the
/// whole-inbox unread count.
@riverpod
Future<NotificationListDto> myNotifications(Ref ref) async {
  final api = ref.watch(notificationsApiProvider);
  return _unwrap(await api.listMine());
}

/// `GET /notifications/unread_count` — the caller's own unread count, for a
/// badge on the bell icon (e.g. in `AccountScreen`).
@riverpod
Future<int> unreadCount(Ref ref) async {
  final api = ref.watch(notificationsApiProvider);
  return _unwrap(await api.unreadCount());
}

/// Owns the single client-safe Tier-3 write: marking one of the caller's own
/// notifications read. On success it invalidates both
/// [myNotificationsProvider] and [unreadCountProvider] so every surface
/// (inbox list + badge) reflects the transition; a failure is swallowed as a
/// no-op state change here — the calling widget already has the tapped
/// notification's row and can show a transient snackbar via `ErrorPresenter`
/// if it chooses to inspect the returned [Result] instead of calling
/// [markRead] directly.
@riverpod
class NotificationController extends _$NotificationController {
  NotificationsApi get _api => ref.read(notificationsApiProvider);

  @override
  void build() {}

  /// Marks [notificationId] read. Idempotent: re-marking an already-read
  /// notification is a success no-op.
  Future<Result<bool>> markRead(String notificationId) async {
    final result = await _api.markRead(notificationId);
    if (result is Ok<bool>) {
      ref.invalidate(myNotificationsProvider);
      ref.invalidate(unreadCountProvider);
    }
    return result;
  }
}
