import 'package:application/src/admin/ports/owner_registry.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/announcement_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owners' own inbox, for what the server does on its own and they
/// alone must know (script 204): who they are, and a message to them.
///
/// The owners are the seats of `admin.platform_owners` (script 285,
/// migration 0217, decision Q01): one primary and his backups, by account
/// id. No e-mail names them anywhere in the code.
abstract interface class OwnerNotices {
  /// The owner the server acts as: the primary, or the first backup when
  /// the primary's account cannot act. `Ok(null)` when no seat can act.
  Future<Result<UserId?>> ownerId();

  /// Whether [user] holds an owner seat, primary or backup, and can act.
  /// Callers fail closed: an error refuses.
  // NK285_01
  Future<Result<bool>> isOwner(UserId user);

  /// Puts [title] and [body] in every owner's inbox, and nobody else's.
  Future<Result<void>> tell({required String title, required String body});
}

/// [OwnerNotices] over the owner seats and the admin announcements, the
/// way the short-day alert reaches the owners (script 190, decided
/// 2026-11-01): one in-app notification to each owner who can act, never
/// to the other admins. No push. A body longer than an announcement takes
/// is cut at its end.
final class OwnerInbox implements OwnerNotices {
  /// Creates the inbox.
  const OwnerInbox({
    required OwnerRegistry owners,
    required AnnouncementRepository announcements,
    required CreateNotification notify,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _owners = owners,
       _announcements = announcements,
       _notify = notify,
       _ids = idGenerator,
       _clock = clock;

  final OwnerRegistry _owners;
  final AnnouncementRepository _announcements;
  final CreateNotification _notify;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  Future<Result<UserId?>> ownerId() async {
    final found = await _owners.activeOwners();
    return switch (found) {
      Err<List<UserId>>(:final error) => Result.err(error),
      Ok<List<UserId>>(:final value) => Result.ok(
        value.isEmpty ? null : value.first,
      ),
    };
  }

  @override
  Future<Result<bool>> isOwner(UserId user) async {
    final found = await _owners.activeOwners();
    return switch (found) {
      Err<List<UserId>>(:final error) => Result.err(error),
      Ok<List<UserId>>(:final value) => Result.ok(value.contains(user)),
    };
  }

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async {
    final found = await _owners.activeOwners();
    if (found is Err<List<UserId>>) {
      return Result.err(found.error);
    }
    final owners = (found as Ok<List<UserId>>).value;
    if (owners.isEmpty) {
      return const Result.err(
        AppError.invariant(
          'notification.owner_admin_missing',
          'No owner seat is held by an active admin account',
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
      authorId: owners.first,
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
    for (final owner in owners) {
      final created = await _notify(
        recipientId: owner,
        kind: NotificationKind.adminAnnouncement,
        subject: NotificationSubject.adminAnnouncement(announcementId: id),
      );
      if (created is Err<bool>) {
        return Result.err(created.error);
      }
    }
    return const Result.ok(null);
  }

  static String _cut(String text, int max) {
    final trimmed = text.trim();
    if (trimmed.length <= max) {
      return trimmed;
    }
    return '${trimmed.substring(0, max - 1)}…';
  }
}
