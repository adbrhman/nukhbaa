import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

// NK290_21
/// Where an admin's announcement stands (script 290, migration 0220).
enum AnnouncementRequestStatus {
  /// Held for an owner seat to publish or reject.
  pending('pending'),

  /// Published to every active player.
  published('published'),

  /// Not approved; nobody received it.
  rejected('rejected');

  const AnnouncementRequestStatus(this.wire);

  /// Its value in `notification.announcement_requests.status` and on the
  /// wire.
  final String wire;

  /// The status whose [wire] is [value], or null.
  static AnnouncementRequestStatus? byWire(String value) {
    for (final AnnouncementRequestStatus s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// An announcement an admin sent while he holds no owner seat (script 290,
/// the owner's decision of 2026-11-20): kept here until an owner seat
/// publishes or rejects it.
final class AnnouncementRequest {
  /// Creates the request.
  const AnnouncementRequest({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.decidedAt,
    this.recipients,
  });

  /// Its id: the admin's own request id, the announcement's id once
  /// published.
  final AnnouncementId id;

  /// The admin who wrote it.
  final UserId authorId;

  /// His display name, as it is now.
  final String authorName;

  /// The headline.
  final String title;

  /// The text.
  final String body;

  /// Where it stands.
  final AnnouncementRequestStatus status;

  /// When it was sent (UTC).
  final DateTime createdAt;

  /// When an owner seat decided (UTC); null while pending.
  final DateTime? decidedAt;

  /// How many inboxes it reached once published; null otherwise.
  final int? recipients;
}

/// Persistence port for the held announcements (script 290, migration
/// 0220). MUST NOT throw; an infrastructure failure is transient.
abstract interface class AnnouncementRequestStore {
  /// Holds [title] and [body] by [author] as the pending request [id]. An
  /// id already held changes nothing: the same "send" pressed again.
  /// Answers the request as it is stored, and whether this call held it.
  Future<Result<(AnnouncementRequest, bool)>> hold({
    required AnnouncementId id,
    required UserId author,
    required String title,
    required String body,
  });

  /// The request [id], or null.
  Future<Result<AnnouncementRequest?>> byId(AnnouncementId id);

  /// The pending requests first, then the latest decided, [limit] in all.
  Future<Result<List<AnnouncementRequest>>> latest({int limit = 50});

  /// [author]'s latest requests, the newest first.
  Future<Result<List<AnnouncementRequest>>> byAuthor(
    UserId author, {
    int limit = 20,
  });

  /// Moves the pending request [id] to [to], decided by [by]; [recipients]
  /// when published. False when it is no longer pending.
  Future<Result<bool>> decide({
    required AnnouncementId id,
    required AnnouncementRequestStatus to,
    required UserId by,
    int? recipients,
  });
}
