/// Use-cases: pictures in the support chat (migration 0188).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A player sends support a picture (a screenshot of a problem). It is a
/// message of its own and rings the admins as a text message does.
///
/// Never throws; returns a typed [Result].
final class SendSupportImage {
  /// Creates the use-case over its collaborators.
  const SendSupportImage({
    required SupportImageRepository images,
    required Clock clock,
  }) : _images = images,
       _clock = clock;

  final SupportImageRepository _images;
  final Clock _clock;

  /// Stores [bytes] of type [mime] from [principal].
  Future<Result<SupportMessageStored>> call({
    required AuthenticatedUser principal,
    required List<int> bytes,
    required String? mime,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final image = SupportImage.parse(bytes, mime);
    if (image is Err<SupportImage>) return Result.err(image.error);
    return _images.addPlayerImage(
      playerId: principal.userId,
      image: (image as Ok<SupportImage>).value,
      at: _clock.nowUtc(),
    );
  }
}

/// An admin answers with a picture, as "دعم نُخبة". Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminReplySupportImage {
  /// Creates the use-case over its collaborators.
  const AdminReplySupportImage({
    required SupportImageRepository images,
    required Clock clock,
  }) : _images = images,
       _clock = clock;

  final SupportImageRepository _images;
  final Clock _clock;

  /// Stores [bytes] of type [mime] from [principal] in [conversationId].
  Future<Result<SupportMessageStored>> call({
    required AuthenticatedUser principal,
    required String conversationId,
    required List<int> bytes,
    required String? mime,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final id = SupportConversationId.tryParse(conversationId);
    if (id is Err<SupportConversationId>) return Result.err(id.error);
    final image = SupportImage.parse(bytes, mime);
    if (image is Err<SupportImage>) return Result.err(image.error);
    return _images.addSupportImage(
      conversationId: (id as Ok<SupportConversationId>).value,
      adminId: principal.userId,
      image: (image as Ok<SupportImage>).value,
      at: _clock.nowUtc(),
    );
  }
}

/// A picture of the player's own conversation; null when the message is
/// not his or carries none, so another player's pictures cannot be read.
///
/// Never throws; returns a typed [Result].
final class GetMySupportImage {
  /// Creates the use-case over its repository.
  const GetMySupportImage({required SupportImageRepository images})
    : _images = images;

  final SupportImageRepository _images;

  /// Reads message [messageId]'s picture for [principal].
  Future<Result<SupportImage?>> call({
    required AuthenticatedUser principal,
    required int? messageId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    if (messageId == null || messageId < 1) return const Result.ok(null);
    return _images.playerImage(
      playerId: principal.userId,
      messageId: messageId,
    );
  }
}

/// A picture of one conversation, for an admin. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminGetSupportImage {
  /// Creates the use-case over its repository.
  const AdminGetSupportImage({required SupportImageRepository images})
    : _images = images;

  final SupportImageRepository _images;

  /// Reads message [messageId]'s picture in [conversationId].
  Future<Result<SupportImage?>> call({
    required AuthenticatedUser principal,
    required String conversationId,
    required int? messageId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final id = SupportConversationId.tryParse(conversationId);
    if (id is Err<SupportConversationId>) return const Result.ok(null);
    if (messageId == null || messageId < 1) return const Result.ok(null);
    return _images.conversationImage(
      conversationId: (id as Ok<SupportConversationId>).value,
      messageId: messageId,
    );
  }
}
