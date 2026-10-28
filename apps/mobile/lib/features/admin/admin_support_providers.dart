/// The admins' side of the support chat (migration 0187, script 167).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// How many conversations hold a player message no admin has read: the
/// count beside «رسائل الدعم» in the admin menu and on «إدارة النخبة». A
/// failed read is null -- no count, not a zero. A plain provider: no code
/// generation.
final FutureProvider<int?> adminSupportWaitingProvider = FutureProvider<int?>((
  ref,
) async {
  final Result<SupportInboxDto> result = await ref
      .watch(adminApiProvider)
      .supportInbox(filter: 'unread');
  return switch (result) {
    Ok<SupportInboxDto>(:final value) => value.unreadConversations,
    Err<SupportInboxDto>() => null,
  };
});
