import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:application/src/notification/ports/announcement_request_store.dart';
import 'package:application/src/notification/publish_announcement.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owners' review of the admins' held announcements (script 290,
/// decided by the owner on 2026-11-20): an owner seat publishes one to
/// every active player, as its author wrote it, or rejects it, and its
/// author reads only that it was not approved.
///
/// Only an owner seat; any other admin is refused (`admin.owner_only`), a
/// player by the role gate, and a failed seat lookup refuses. A request no
/// longer pending is `announcement.already_decided`. Never throws.
// NK290_03
final class OwnerAnnouncementReview {
  /// Creates the use-case over its collaborators.
  const OwnerAnnouncementReview({
    required AnnouncementRequestStore requests,
    required PublishAnnouncement publish,
    required OwnerNotices owners,
  }) : _requests = requests,
       _publish = publish,
       _owners = owners;

  final AnnouncementRequestStore _requests;
  final PublishAnnouncement _publish;
  final OwnerNotices _owners;

  /// The pending requests first, then the latest decided.
  Future<Result<List<AnnouncementRequest>>> list({
    required AuthenticatedUser principal,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    return _requests.latest();
  }

  /// Publishes the held request [requestId]; answers how many inboxes it
  /// reached.
  Future<Result<int>> publish({
    required AuthenticatedUser principal,
    required String requestId,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final Result<AnnouncementRequest> found = await _pending(requestId);
    if (found is Err<AnnouncementRequest>) return Result.err(found.error);
    final AnnouncementRequest request =
        (found as Ok<AnnouncementRequest>).value;
    // Delivered first: the fan-out is idempotent per announcement, so a
    // second press, or both owners at once, reaches nobody twice.
    final Result<int> sent = await _publish.publishAs(
      author: request.authorId,
      id: request.id,
      title: request.title,
      body: request.body,
    );
    if (sent is Err<int>) return Result.err(sent.error);
    final int recipients = (sent as Ok<int>).value;
    final Result<bool> moved = await _requests.decide(
      id: request.id,
      to: AnnouncementRequestStatus.published,
      by: (gate as Ok<UserId>).value,
      recipients: recipients,
    );
    if (moved is Err<bool>) return Result.err(moved.error);
    return Result.ok(recipients);
  }

  /// Rejects the held request [requestId]: nobody receives it.
  Future<Result<void>> reject({
    required AuthenticatedUser principal,
    required String requestId,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final Result<AnnouncementRequest> found = await _pending(requestId);
    if (found is Err<AnnouncementRequest>) return Result.err(found.error);
    final Result<bool> moved = await _requests.decide(
      id: (found as Ok<AnnouncementRequest>).value.id,
      to: AnnouncementRequestStatus.rejected,
      by: (gate as Ok<UserId>).value,
    );
    if (moved is Err<bool>) return Result.err(moved.error);
    if (!(moved as Ok<bool>).value) return const Result.err(_decided);
    return const Result.ok(null);
  }

  Future<Result<AnnouncementRequest>> _pending(String requestId) async {
    final idResult = AnnouncementId.tryParse(requestId);
    if (idResult is Err<AnnouncementId>) return const Result.err(_notFound);
    final Result<AnnouncementRequest?> found = await _requests.byId(
      (idResult as Ok<AnnouncementId>).value,
    );
    if (found is Err<AnnouncementRequest?>) return Result.err(found.error);
    final AnnouncementRequest? request =
        (found as Ok<AnnouncementRequest?>).value;
    if (request == null) return const Result.err(_notFound);
    if (request.status != AnnouncementRequestStatus.pending) {
      return const Result.err(_decided);
    }
    return Result.ok(request);
  }

  /// The id of [principal] when he holds an owner seat; refused otherwise.
  Future<Result<UserId>> _ownerOnly(AuthenticatedUser principal) async {
    final Result<AuthenticatedUser> role = Authorization.requireRole(
      principal,
      PlatformRole.admin,
    );
    if (role is Err<AuthenticatedUser>) return Result.err(role.error);
    final bool seated = switch (await _owners.isOwner(principal.userId)) {
      Ok<bool>(:final value) => value,
      Err<bool>() => false,
    };
    if (!seated) {
      return const Result.err(
        AppError.invariant('admin.owner_only', 'مراجعة الإعلانات للمالك وحده.'),
      );
    }
    return Result.ok(principal.userId);
  }

  static const AppError _notFound = AppError.invariant(
    'announcement.request_not_found',
    'لم يُعثر على هذا الإعلان.',
  );

  static const AppError _decided = AppError.invariant(
    'announcement.already_decided',
    'حُسم هذا الإعلان من قبل.',
  );
}
