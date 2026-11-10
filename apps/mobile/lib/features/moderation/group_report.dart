/// Report a friends' league by its name (script 253, Play release audit F5).
///
/// A league's name is free text its owner types, and every member reads it,
/// so Google Play's user-generated-content policy wants a way to report it,
/// as a player's name already has ([showPlayerActions]). The report goes
/// the same way: to the reporter's own support chat (migration 0187), which
/// reaches the owner with a notification. It carries the name, the league's
/// id and the reason, so the admin finds the league and acts with the tools
/// he already has. Nothing is hidden on the phone: the reporter can leave
/// the league from the same screen.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../support/support_providers.dart';
import 'player_actions.dart';

/// The reasons a league report can give, in the order they are offered.
const List<String> groupReportReasons = <String>[
  'اسم مسيء أو مخالف',
  'انتحال اسم جهة أو شخص',
  'محتوى غير لائق آخر',
  'سبب آخر',
];

/// The message a league report puts in the support chat.
String groupReportMessage({
  required String groupName,
  required String groupId,
  required String reason,
}) =>
    'بلاغ عن اسم دوري\n'
    'الاسم: $groupName\n'
    'المعرّف: $groupId\n'
    'السبب: $reason';

/// Asks why the league [groupName] (id [groupId]) is reported, then sends
/// the report to the support chat and says what happened.
Future<void> showGroupReport(
  BuildContext context, {
  required String groupName,
  required String groupId,
}) async {
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String? reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) => _GroupReasonSheet(groupName: groupName),
  );
  if (reason == null) return;
  final Result<SupportMessageDto> result = await container
      .read(supportApiProvider)
      .send(
        groupReportMessage(
          groupName: groupName,
          groupId: groupId,
          reason: reason,
        ),
      );
  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (result) {
        Ok<SupportMessageDto>() => reportSentMessage,
        Err<SupportMessageDto>(:final error) => ErrorPresenter.message(error),
      }),
    ),
  );
}

class _GroupReasonSheet extends StatelessWidget {
  const _GroupReasonSheet({required this.groupName});

  final String groupName;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'الإبلاغ عن اسم «$groupName»',
                key: const Key('groupReport.title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'يصل بلاغك إلى فريق نُخبة. ما السبب؟',
                style: context.text.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
            for (int i = 0; i < groupReportReasons.length; i++)
              ListTile(
                key: Key('groupReport.reason.$i'),
                title: Text(groupReportReasons[i]),
                onTap: () => Navigator.of(context).pop(groupReportReasons[i]),
              ),
          ],
        ),
      ),
    );
  }
}
