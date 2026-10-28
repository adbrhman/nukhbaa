import 'dart:typed_data';

import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the caller's own chat with Nukhbaa support (migration
/// 0187, scripts 165-166).
///
/// Every route is the caller's own: the server finds the conversation by
/// the verified token, never by an id this client sends. Every method
/// returns a typed [Result] and never throws.
final class SupportApi {
  /// Creates the client over the shared [ApiTransport].
  const SupportApi(this._transport);

  final ApiTransport _transport;

  /// `GET /me/support/messages` -- the newest page of the chat, oldest
  /// first, or the [limit] messages before the message id [before].
  Future<Result<SupportThreadDto>> thread({int? before, int? limit}) {
    final Map<String, String> query = <String, String>{
      if (before != null) 'before': '$before',
      if (limit != null) 'limit': '$limit',
    };
    return _transport.getObject<SupportThreadDto>(
      '/me/support/messages',
      query: query.isEmpty ? null : query,
      parse: SupportThreadDto.fromJson,
    );
  }

  /// `POST /me/support/messages` -- sends [body] to support; answers the
  /// message as stored.
  Future<Result<SupportMessageDto>> send(String body) {
    return _transport.postObject<SupportMessageDto>(
      '/me/support/messages',
      body: SupportSendDto(body: body).toJson(),
      parse: SupportMessageDto.fromJson,
    );
  }

  /// `POST /me/support/read` -- the caller read support's answers; answers
  /// how many were marked.
  Future<Result<int>> markRead() {
    return _transport.postObject<int>(
      '/me/support/read',
      body: const <String, Object?>{},
      parse: (json) => SupportCountDto.fromJson(json).count,
    );
  }

  /// `POST /me/support/images` -- sends support a picture (migration 0188):
  /// the raw [bytes] under [contentType]; answers the message as stored.
  Future<Result<SupportMessageDto>> sendImage(
    List<int> bytes, {
    required String contentType,
  }) {
    return _transport.postBytes<SupportMessageDto>(
      '/me/support/images',
      bytes: bytes,
      contentType: contentType,
      parse: SupportMessageDto.fromJson,
    );
  }

  /// `GET /me/support/messages/{messageId}/image` -- a picture of the
  /// caller's own chat; `Ok(null)` when there is none to read.
  Future<Result<Uint8List?>> image(int messageId) =>
      _transport.getBytes('/me/support/messages/$messageId/image');

  /// `GET /me/support/unread` -- support's answers the caller has not read.
  Future<Result<int>> unread() {
    return _transport.getObject<int>(
      '/me/support/unread',
      parse: (json) => SupportCountDto.fromJson(json).count,
    );
  }
}
