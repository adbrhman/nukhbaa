import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:application/src/notification/ports/announcement_request_store.dart';
import 'package:application/src/notification/publish_announcement.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What became of an announcement an admin sent (script 290).
final class AnnouncementSubmitted {
  /// Creates the outcome.
  const AnnouncementSubmitted({required this.status, this.recipients = 0});

  /// Published at once, held for an owner seat, or already rejected.
  final AnnouncementRequestStatus status;

  /// How many inboxes it reached now (0 unless published by this call).
  final int recipients;
}

/// An admin sends an announcement to every active player (script 290,
/// decided by the owner on 2026-11-20, amending Q07).
///
/// An owner seat's announcement is published at once ([PublishAnnouncement]).
/// Any other admin's is held (`notification.announcement_requests`, migration
/// 0220) until an owner seat publishes or rejects it
/// ([OwnerAnnouncementReview]); the owners are told in their inbox. The
/// admin reads that it will be published after its content is reviewed,
/// never who reviews it. A seat lookup that fails holds it, never publishes
/// it. The same request id sent again is the same announcement.
///
/// Never throws.
// NK290_02
final class SubmitAnnouncement {
  /// Creates the use-case over its collaborators.
  const SubmitAnnouncement({
    required PublishAnnouncement publish,
    required AnnouncementRequestStore requests,
    required OwnerNotices owners,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _publish = publish,
       _requests = requests,
       _owners = owners,
       _ids = idGenerator,
       _clock = clock;

  final PublishAnnouncement _publish;
  final AnnouncementRequestStore _requests;
  final OwnerNotices _owners;
  final IdGenerator _ids;
  final Clock _clock;

  /// Sends [title]/[body] for admin [principal], as [requestId] when the
  /// app gave one.
  Future<Result<AnnouncementSubmitted>> call({
    required AuthenticatedUser principal,
    required String title,
    required String body,
    String? requestId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final bool owner = switch (await _owners.isOwner(principal.userId)) {
      Ok<bool>(:final value) => value,
      Err<bool>() => false,
    };
    if (owner) {
      final Result<int> sent = await _publish(
        principal: principal,
        title: title,
        body: body,
        requestId: requestId,
      );
      return switch (sent) {
        Ok<int>(:final value) => Result.ok(
          AnnouncementSubmitted(
            status: AnnouncementRequestStatus.published,
            recipients: value,
          ),
        ),
        Err<int>(:final error) => Result.err(error),
      };
    }

    final idResult = AnnouncementId.tryParse(requestId ?? _ids.newUuid());
    if (idResult is Err<AnnouncementId>) return Result.err(idResult.error);
    final AnnouncementId id = (idResult as Ok<AnnouncementId>).value;
    // The same checks as a published one: blank or long text is refused.
    final built = Announcement.create(
      id: id,
      authorId: principal.userId,
      title: title,
      body: body,
      createdAt: _clock.nowUtc(),
    );
    if (built is Err<Announcement>) return Result.err(built.error);
    final Announcement checked = (built as Ok<Announcement>).value;

    final held = await _requests.hold(
      id: id,
      author: principal.userId,
      title: checked.title,
      body: checked.body,
    );
    if (held is Err<(AnnouncementRequest, bool)>) {
      return Result.err(held.error);
    }
    final (AnnouncementRequest request, bool fresh) =
        (held as Ok<(AnnouncementRequest, bool)>).value;
    if (fresh) {
      // Best effort: the request is kept, and the owners' page lists it.
      await _owners.tell(
        title: 'إعلان ينتظر مراجعتك',
        body:
            '«${checked.title}» من ${request.authorName}. انشره أو ارفضه من '
            '«الإدارة العامة للمالك» ← «الإعلانات».',
      );
    }
    return Result.ok(AnnouncementSubmitted(status: request.status));
  }

  /// [principal]'s latest announcements and where each stands.
  Future<Result<List<AnnouncementRequest>>> mine({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _requests.byAuthor(principal.userId);
  }
}
