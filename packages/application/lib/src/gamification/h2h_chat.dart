/// Use-cases: the chat of a head-to-head group (migration 0216, script 281).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/ports/h2h_chat_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What a player does in the chat of his own group: read it, write in it,
/// mark it read and accept its rules. Every method works on the group the
/// caller sits in, found by his id and never by an id from the request.
/// Reporting and blocking are script 225's system, outside the server (a
/// report reaches the owner through the support chat, a block is kept on the
/// phone).
///
/// Never throws; every method returns a typed [Result].
final class H2hChat {
  /// Creates the use-cases over their collaborators.
  const H2hChat({required H2hChatRepository chats, required Clock clock})
    : _chats = chats,
      _clock = clock;

  /// How many messages a page holds when the caller names no limit.
  static const int defaultLimit = 50;

  /// The most messages one page may hold.
  static const int maxLimit = 100;

  final H2hChatRepository _chats;
  final Clock _clock;

  static int _limit(int? raw) {
    final int value = raw ?? defaultLimit;
    if (value < 1) return 1;
    if (value > maxLimit) return maxLimit;
    return value;
  }

  static Result<AuthenticatedUser> _player(AuthenticatedUser principal) =>
      Authorization.requireRole(principal, PlatformRole.user);

  /// The newest page of [principal]'s group chat, or the messages after the
  /// message id [afterId].
  Future<Result<H2hChatPage>> page({
    required AuthenticatedUser principal,
    int? afterId,
    int? limit,
  }) async {
    final auth = _player(principal);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _chats.page(
      playerId: principal.userId,
      afterId: afterId,
      limit: _limit(limit),
    );
  }

  /// Stores [text] from [principal] in his group.
  Future<Result<H2hChatMessage>> send({
    required AuthenticatedUser principal,
    required String? text,
  }) async {
    final auth = _player(principal);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final body = H2hChatBody.parse(text);
    if (body is Err<H2hChatBody>) return Result.err(body.error);
    return _chats.send(
      playerId: principal.userId,
      body: (body as Ok<H2hChatBody>).value,
      at: _clock.nowUtc(),
    );
  }

  /// [principal] has read his group's chat.
  Future<Result<void>> markRead({required AuthenticatedUser principal}) async {
    final auth = _player(principal);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _chats.markRead(playerId: principal.userId, at: _clock.nowUtc());
  }

  /// [principal] accepts the chat rules: until he does, he cannot write.
  Future<Result<void>> acceptRules({
    required AuthenticatedUser principal,
  }) async {
    final auth = _player(principal);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _chats.acceptRules(playerId: principal.userId, at: _clock.nowUtc());
  }
}
