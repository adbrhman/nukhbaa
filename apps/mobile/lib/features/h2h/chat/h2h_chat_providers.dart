/// The player's chat with his head-to-head group (migration 0216, script
/// 282).
library;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// The typed client of the chat of the player's own group. The server finds
/// the group by the signed-in player; nothing here names one.
final Provider<H2hChatApi> h2hChatApiProvider = Provider<H2hChatApi>(
  (ref) => H2hChatApi(ref.watch(apiTransportProvider)),
);
