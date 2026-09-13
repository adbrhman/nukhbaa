import 'package:application/src/notification/list_my_notifications.dart';
import 'package:application/src/notification/ports/announcement_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One row of the caller's inbox: the stored [notification] plus, for an
/// `adminAnnouncement`, the [announcement] whose text it references.
///
/// The pairing is done HERE rather than by widening `Notification`, because
/// the notification row deliberately carries no prose (Notifications decision
/// #1): the text is a separate aggregate, joined only at read time.
final class NotificationFeedItem {
  /// Creates a feed item.
  const NotificationFeedItem({required this.notification, this.announcement});

  /// The stored notification.
  final Notification notification;

  /// The referenced announcement text, or null for every other kind (and for
  /// an announcement that no longer exists).
  final Announcement? announcement;
}

/// Query use-case: the caller's own inbox, newest-first, with the
/// announcement text already resolved so the client renders a readable row
/// instead of a bare kind token.
///
/// Composes [ListMyNotifications] (which owns the recipient-only gate and the
/// limit clamp — decision #4) with one batched announcement read. Two queries,
/// never N: the ids are collected from the page and fetched together.
///
/// Never throws; returns a typed [Result].
final class ListMyNotificationFeed {
  /// Creates the use-case over its collaborators.
  const ListMyNotificationFeed({
    required ListMyNotifications list,
    required AnnouncementRepository announcements,
  }) : _list = list,
       _announcements = announcements;

  final ListMyNotifications _list;
  final AnnouncementRepository _announcements;

  /// Reads [principal]'s own inbox, newest-first. [limit] is clamped by the
  /// wrapped [ListMyNotifications].
  Future<Result<List<NotificationFeedItem>>> call({
    required AuthenticatedUser principal,
    int? limit,
  }) async {
    final listed = await _list(principal: principal, limit: limit);
    if (listed is Err<List<Notification>>) {
      return Result.err(listed.error);
    }
    final notifications = (listed as Ok<List<Notification>>).value;

    final ids = <String, AnnouncementId>{};
    for (final notification in notifications) {
      final id = notification.subject.announcementId;
      if (id != null) {
        ids[id.value] = id;
      }
    }
    if (ids.isEmpty) {
      return Result.ok([
        for (final notification in notifications)
          NotificationFeedItem(notification: notification),
      ]);
    }

    final found = await _announcements.findByIds(ids.values.toList());
    if (found is Err<List<Announcement>>) {
      return Result.err(found.error);
    }
    final byId = <String, Announcement>{
      for (final announcement in (found as Ok<List<Announcement>>).value)
        announcement.id.value: announcement,
    };

    return Result.ok([
      for (final notification in notifications)
        NotificationFeedItem(
          notification: notification,
          announcement: byId[notification.subject.announcementId?.value],
        ),
    ]);
  }
}
