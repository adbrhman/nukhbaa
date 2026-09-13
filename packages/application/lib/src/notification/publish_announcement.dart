import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/announcement_repository.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: an admin publishes one instruction to every active user.
///
/// The only client-callable *creation* path in Notifications, and the single
/// exception to "creation is server-triggered only" (decision #4) — it is
/// admin-gated exactly like the other admin commands, and the recipients are
/// resolved server-side from the audience query, never from the request body.
///
/// Shape of one publish:
/// 1. authorize the caller as an **admin** (Axioms 2/5 — only the platform
///    speaks to everyone);
/// 2. store the text ONCE as an [Announcement] (the free text lives there, not
///    on the notification rows — Notifications decision #1);
/// 3. fan out one idempotent [CreateNotification] per recipient, keyed on the
///    announcement id, so a retried publish of the SAME announcement never
///    doubles a user's inbox;
/// 4. push to every device of the users who actually received a new row.
///
/// Step 4 is **best effort**: an unreachable phone must never fail a publish
/// that already landed in every inbox, so push failures are dropped and the
/// use-case still answers `Ok`.
///
/// Returns the number of users whose inbox gained a new notification.
final class PublishAnnouncement {
  /// Creates the use-case over its collaborators.
  const PublishAnnouncement({
    required AnnouncementRepository announcements,
    required CreateNotification create,
    required PushSender sender,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _announcements = announcements,
       _create = create,
       _sender = sender,
       _idGenerator = idGenerator,
       _clock = clock;

  final AnnouncementRepository _announcements;
  final CreateNotification _create;
  final PushSender _sender;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Publishes [title]/[body] on behalf of admin [principal].
  Future<Result<int>> call({
    required AuthenticatedUser principal,
    required String title,
    required String body,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final idResult = AnnouncementId.tryParse(_idGenerator.newUuid());
    if (idResult is Err<AnnouncementId>) {
      return Result.err(idResult.error);
    }
    final id = (idResult as Ok<AnnouncementId>).value;

    final built = Announcement.create(
      id: id,
      authorId: principal.userId,
      title: title,
      body: body,
      createdAt: _clock.nowUtc(),
    );
    if (built is Err<Announcement>) {
      return Result.err(built.error);
    }
    final announcement = (built as Ok<Announcement>).value;

    final saved = await _announcements.save(announcement);
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }

    final audienceResult = await _announcements.audience();
    if (audienceResult is Err<List<AnnouncementRecipient>>) {
      return Result.err(audienceResult.error);
    }
    final audience = (audienceResult as Ok<List<AnnouncementRecipient>>).value;

    final subject = NotificationSubject.adminAnnouncement(announcementId: id);
    final tokens = <String>[];
    var delivered = 0;
    for (final recipient in audience) {
      final created = await _create(
        recipientId: recipient.userId,
        kind: NotificationKind.adminAnnouncement,
        subject: subject,
      );
      if (created is Err<bool>) {
        continue;
      }
      if (!(created as Ok<bool>).value) {
        // Already in this user's inbox: a replayed publish of the same
        // announcement, which must not ring the same phone twice.
        continue;
      }
      delivered++;
      tokens.addAll(recipient.tokens);
    }

    if (tokens.isNotEmpty) {
      // Deliberately unchecked: the inbox rows are already written, and a
      // transport failure must not turn a successful publish into an error.
      await _sender.send(
        tokens: tokens,
        title: announcement.title,
        body: announcement.body,
      );
    }

    return Result.ok(delivered);
  }
}
