/// The player's chat with Nukhbaa support (migration 0187, script 166).
library;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// The typed client of the player's own support chat.
final Provider<SupportApi> supportApiProvider = Provider<SupportApi>(
  (ref) => SupportApi(ref.watch(apiTransportProvider)),
);

/// Support's answers the player has not read: the count on "تواصل مع
/// المطوّر". Read again when the chat closes, when the app comes back to
/// the foreground and when a push arrives while it is open. A failed read
/// shows no count rather than an error on the account tab.
final FutureProvider<int> supportUnreadProvider = FutureProvider<int>((
  ref,
) async {
  final Result<int> result = await ref.watch(supportApiProvider).unread();
  return switch (result) {
    Ok<int>(:final value) => value,
    Err<int>() => 0,
  };
});
