import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the chat of the caller's own head-to-head group
/// (migration 0216, script 281).
///
/// Every route is the caller's own: the server finds his group by the
/// verified token, never by an id this client sends. Every method returns a
/// typed [Result] and never throws.
final class H2hChatApi {
  /// Creates the client over the shared [ApiTransport].
  const H2hChatApi(this._transport);

  final ApiTransport _transport;

  static const String _base = '/me/h2h-league/chat';

  /// `GET /me/h2h-league/chat` -- the newest page of the chat, oldest
  /// first, or the messages after the message id [after].
  Future<Result<H2hChatPageDto>> page({int? after, int? limit}) {
    final Map<String, String> query = <String, String>{
      if (after != null) 'after': '$after',
      if (limit != null) 'limit': '$limit',
    };
    return _transport.getObject<H2hChatPageDto>(
      _base,
      query: query.isEmpty ? null : query,
      parse: H2hChatPageDto.fromJson,
    );
  }

  /// `POST /me/h2h-league/chat` -- sends [body] to the group; answers the
  /// message as stored.
  Future<Result<H2hChatMessageDto>> send(String body) {
    return _transport.postObject<H2hChatMessageDto>(
      _base,
      body: <String, Object?>{'body': body},
      parse: H2hChatMessageDto.fromJson,
    );
  }

  /// `POST /me/h2h-league/chat/read` -- the caller read the chat.
  Future<Result<void>> markRead() => _ack(
    _transport.postObject<H2hChatAckDto>(
      '$_base/read',
      body: const <String, Object?>{},
      parse: H2hChatAckDto.fromJson,
    ),
  );

  /// `POST /me/h2h-league/chat/rules` -- the caller accepts the chat rules.
  Future<Result<void>> acceptRules() => _ack(
    _transport.postObject<H2hChatAckDto>(
      '$_base/rules',
      body: const <String, Object?>{},
      parse: H2hChatAckDto.fromJson,
    ),
  );

  static Future<Result<void>> _ack(Future<Result<H2hChatAckDto>> call) async {
    final Result<H2hChatAckDto> result = await call;
    return switch (result) {
      Ok<H2hChatAckDto>() => const Result.ok(null),
      Err<H2hChatAckDto>(:final error) => Result.err(error),
    };
  }
}
