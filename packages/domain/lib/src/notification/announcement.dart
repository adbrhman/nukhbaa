import 'package:domain/src/identity/user_id.dart';
import 'package:domain/src/notification/announcement_id.dart';
import 'package:shared/shared.dart';

/// One administrative broadcast: the free text an admin sends to every active
/// user, written ONCE and referenced by each recipient's `Notification`
/// (migration `0043_admin_announcements.sql`).
///
/// This is where the free text lives — deliberately NOT on `Notification`,
/// which stays a pure reference row carrying no prose (Notifications decision
/// #1 / ADR-001). A broadcast to N users is one [Announcement] and N
/// notifications pointing at it.
///
/// Carries **NO points field** (Axiom 5 — nothing in Notifications is a second
/// points source). Append-only in practice: there is no edit or delete path in
/// the domain, mirroring the audit trail. Value-comparable.
final class Announcement {
  const Announcement._({
    required this.id,
    required this.authorId,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  /// Rehydrates an [Announcement] from already-trusted stored fields (used by
  /// the infrastructure mapper). Performs no validation beyond typing —
  /// callers creating a *new* announcement must use [create].
  const Announcement.fromStored({
    required this.id,
    required this.authorId,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  /// The longest permitted title, in characters.
  static const int maxTitleLength = 120;

  /// The longest permitted body, in characters.
  static const int maxBodyLength = 1000;

  /// Creates a new announcement from untrusted [title]/[body] text.
  ///
  /// Both are trimmed; a blank value is a typed validation error rather than
  /// an empty notification nobody can read, and an over-long value is refused
  /// here rather than by the database check constraint. [createdAt] must be a
  /// UTC instant so the newest-first ordering is unambiguous.
  static Result<Announcement> create({
    required AnnouncementId id,
    required UserId authorId,
    required String title,
    required String body,
    required DateTime createdAt,
  }) {
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty) {
      return const Result.err(
        AppError.validation(
          'notification.announcement_title_empty',
          'Announcement title is required',
        ),
      );
    }
    if (trimmedTitle.length > maxTitleLength) {
      return const Result.err(
        AppError.validation(
          'notification.announcement_title_too_long',
          'Announcement title must be at most $maxTitleLength characters',
        ),
      );
    }
    if (trimmedBody.isEmpty) {
      return const Result.err(
        AppError.validation(
          'notification.announcement_body_empty',
          'Announcement body is required',
        ),
      );
    }
    if (trimmedBody.length > maxBodyLength) {
      return const Result.err(
        AppError.validation(
          'notification.announcement_body_too_long',
          'Announcement body must be at most $maxBodyLength characters',
        ),
      );
    }
    if (!createdAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'notification.announcement_created_at_not_utc',
          'createdAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      Announcement._(
        id: id,
        authorId: authorId,
        title: trimmedTitle,
        body: trimmedBody,
        createdAt: createdAt,
      ),
    );
  }

  /// The announcement identity.
  final AnnouncementId id;

  /// The admin who published it.
  final UserId authorId;

  /// The short headline shown in the notification row.
  final String title;

  /// The instruction text itself.
  final String body;

  /// When it was published (UTC).
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is Announcement &&
      other.id == id &&
      other.authorId == authorId &&
      other.title == title &&
      other.body == body &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, authorId, title, body, createdAt);

  @override
  String toString() => 'Announcement(${id.value}, $title)';
}
