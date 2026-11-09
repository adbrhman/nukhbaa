/// Report or block a player, from the menu beside a name (script 225).
///
/// Google Play's user-generated-content policy asks for an in-app system to
/// report and to block objectionable users. The report goes to the player's
/// own support chat (migration 0187), which already reaches the owner with a
/// notification and which the admin answers; it carries the name, the
/// participant id and the reason, so the admin can rename or suspend the
/// account with the tools he already has. The block is kept on the phone
/// (see [BlockedPlayers]).
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../support/support_providers.dart';
import 'blocked_players.dart';

/// The reasons a report can give, in the order they are offered.
const List<String> playerReportReasons = <String>[
  'اسم مسيء أو مخالف',
  'صورة شخصية مسيئة',
  'انتحال شخصية أو اسم غير حقيقي',
  'إساءة أو مضايقة',
  'سبب آخر',
];

/// The message a report puts in the support chat.
String playerReportMessage({
  required String displayName,
  required String participantId,
  required String reason,
}) =>
    'بلاغ عن لاعب\n'
    'الاسم: $displayName\n'
    'رقم المشارك: $participantId\n'
    'السبب: $reason';

/// What the snackbar says once a report is sent.
const String reportSentMessage = 'وصل بلاغك إلى فريق نُخبة، شكراً لك.';

/// What the snackbar says once a player is blocked.
const String playerBlockedMessage =
    'تم حظر اللاعب. يمكنك إلغاء الحظر من الإعدادات.';

/// What the snackbar says once a block is lifted.
const String playerUnblockedMessage = 'تم إلغاء حظر اللاعب.';

enum _PlayerAction { report, block, unblock }

/// Opens the menu of the player called [displayName] (their participant id
/// in the season shown is [participantId]) and carries out the choice.
Future<void> showPlayerActions(
  BuildContext context, {
  required String displayName,
  required String participantId,
}) async {
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool blocked = container
      .read(blockedPlayersProvider)
      .containsKey(blockKeyOf(displayName));
  final _PlayerAction? action = await showModalBottomSheet<_PlayerAction>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) =>
        _ActionsSheet(displayName: displayName, blocked: blocked),
  );
  if (action == null) return;
  switch (action) {
    case _PlayerAction.block:
      await container.read(blockedPlayersProvider.notifier).block(displayName);
      messenger.showSnackBar(
        const SnackBar(content: Text(playerBlockedMessage)),
      );
    case _PlayerAction.unblock:
      await container
          .read(blockedPlayersProvider.notifier)
          .unblock(blockKeyOf(displayName));
      messenger.showSnackBar(
        const SnackBar(content: Text(playerUnblockedMessage)),
      );
    case _PlayerAction.report:
      if (!context.mounted) return;
      final String? reason = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheet) => const _ReasonSheet(),
      );
      if (reason == null) return;
      final Result<SupportMessageDto> result = await container
          .read(supportApiProvider)
          .send(
            playerReportMessage(
              displayName: displayName,
              participantId: participantId,
              reason: reason,
            ),
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            Ok<SupportMessageDto>() => reportSentMessage,
            Err<SupportMessageDto>(:final error) => ErrorPresenter.message(
              error,
            ),
          }),
        ),
      );
  }
}

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.displayName, required this.blocked});

  final String displayName;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              displayName,
              key: const Key('playerActions.name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ListTile(
            key: const Key('playerActions.report'),
            leading: const Icon(Icons.flag_outlined),
            title: const Text('الإبلاغ عن هذا اللاعب'),
            subtitle: const Text('يصل بلاغك إلى فريق نُخبة'),
            onTap: () => Navigator.of(context).pop(_PlayerAction.report),
          ),
          if (blocked)
            ListTile(
              key: const Key('playerActions.unblock'),
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('إلغاء حظر اللاعب'),
              onTap: () => Navigator.of(context).pop(_PlayerAction.unblock),
            )
          else
            ListTile(
              key: const Key('playerActions.block'),
              leading: const Icon(Icons.block_outlined),
              title: const Text('حظر اللاعب'),
              subtitle: const Text('يختفي اسمه وصورته من شاشاتك'),
              onTap: () => Navigator.of(context).pop(_PlayerAction.block),
            ),
        ],
      ),
    );
  }
}

class _ReasonSheet extends StatelessWidget {
  const _ReasonSheet();

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              'ما سبب البلاغ؟',
              style: context.text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (int i = 0; i < playerReportReasons.length; i++)
            ListTile(
              key: Key('playerReport.reason.$i'),
              title: Text(playerReportReasons[i]),
              onTap: () => Navigator.of(context).pop(playerReportReasons[i]),
            ),
        ],
      ),
    );
  }
}
