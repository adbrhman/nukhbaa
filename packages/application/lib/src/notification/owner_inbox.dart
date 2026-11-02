import 'package:application/src/admin/ports/user_admin_repository.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/announcement_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owner admin's own inbox, for what the server does on its own and he
/// alone must know (script 204): who he is, and a message to him.
abstract interface class OwnerNotices {
  /// The owner admin's account, or `Ok(null)` when no active admin account
  /// has the owner's e-mail.
  Future<Result<UserId?>> ownerId();

  /// Puts [title] and [body] in the owner's inbox, and nobody else's.
  Future<Result<void>> tell({required String title, required String body});
}

/// [OwnerNotices] over the admin announcements, the way the short-day alert
/// reaches the owner (script 190, decided 2026-11-01): one in-app
/// notification to the active admin account whose e-mail is [email], never
/// to the other admins. No push. A body longer than an announcement takes
/// is cut at its end.
final class OwnerInbox implements OwnerNotices {
  /// Creates the inbox.
  const OwnerInbox({
    required this.email,
    required UserAdminRepository users,
    required AnnouncementRepository announcements,
    required CreateNotification notify,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _users = users,
       _announcements = announcements,
       _notify = notify,
       _ids = idGenerator,
       _clock = clock;

  /// The owner admin's e-mail.
  final String email;

  final UserAdminRepository _users;
  final AnnouncementRepository _announcements;
  final CreateNotification _notify;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<UserId?>> ownerId() async {
    final found = await _users.listUsers(search: email.trim(), limit: 5);
    if (found is Err<List<User>>) {
      return Result.err(found.error);
    }
    final wanted = email.trim().toLowerCase();
    for (final user in (found as Ok<List<User>>).value) {
      if ((user.email ?? '').trim().toLowerCase() == wanted &&
          user.role == PlatformRole.admin &&
          user.status.canAct) {
        return Result.ok(user.id);
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async {
    final ownerResult = await ownerId();
    if (ownerResult is Err<UserId?>) {
      return Result.err(ownerResult.error);
    }
    final owner = (ownerResult as Ok<UserId?>).value;
    if (owner == null) {
      return const Result.err(
        AppError.invariant(
          'notification.owner_admin_missing',
          'No active admin account has the alert e-mail',
        ),
      );
    }

    final idResult = AnnouncementId.tryParse(_ids.newUuid());
    if (idResult is Err<AnnouncementId>) {
      return Result.err(idResult.error);
    }
    final id = (idResult as Ok<AnnouncementId>).value;
    final built = Announcement.create(
      id: id,
      authorId: owner,
      title: _cut(title, Announcement.maxTitleLength),
      body: _cut(body, Announcement.maxBodyLength),
      createdAt: _clock.nowUtc(),
    );
    if (built is Err<Announcement>) {
      return Result.err(built.error);
    }
    final saved = await _announcements.save((built as Ok<Announcement>).value);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }
    final created = await _notify(
      recipientId: owner,
      kind: NotificationKind.adminAnnouncement,
      subject: NotificationSubject.adminAnnouncement(announcementId: id),
    );
    return switch (created) {
      Ok<bool>() => const Result.ok(null),
      Err<bool>(:final error) => Result.err(error),
    };
  }

  static String _cut(String text, int max) {
    final trimmed = text.trim();
    if (trimmed.length <= max) {
      return trimmed;
    }
    return '${trimmed.substring(0, max - 1)}…';
  }
}
