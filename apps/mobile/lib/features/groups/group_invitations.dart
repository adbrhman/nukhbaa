/// Invitations to a friends' league (migration 0097), from the invited
/// player's side: who invited, to which league, and the answer. The inbox
/// row of a `group_invited` notification shows them with accept and
/// decline; accepting joins the league.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/design/app_typography.dart';
import '../../core/providers.dart';
import 'groups_providers.dart';

/// `GET /groups/invitations`: the caller's own invitations, newest first.
final myGroupInvitationsProvider =
    FutureProvider.autoDispose<GroupInvitationsDto>((ref) async {
      final GroupsApi api = ref.watch(groupsApiProvider);
      return switch (await api.myInvitations()) {
        Ok<GroupInvitationsDto>(:final value) => value,
        Err<GroupInvitationsDto>(:final error) => throw error,
      };
    }, retry: (_, _) => null);

/// Under an inbox row about an invitation to [groupId]'s league: who
/// invited and to which league, then accept and decline while it waits, or
/// the answer once given.
class GroupInvitationActions extends ConsumerStatefulWidget {
  /// Creates the actions for the invitation to [groupId].
  const GroupInvitationActions({required this.groupId, super.key});

  /// The league the notification is about.
  final String? groupId;

  @override
  ConsumerState<GroupInvitationActions> createState() =>
      _GroupInvitationActionsState();
}

class _GroupInvitationActionsState
    extends ConsumerState<GroupInvitationActions> {
  bool _busy = false;

  Future<void> _answer(GroupInvitationDto invitation, bool accept) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final GroupsApi api = ref.read(groupsApiProvider);
    setState(() => _busy = true);
    final Result<String> result = accept
        ? await api.acceptInvitation(invitation.id)
        : await api.declineInvitation(invitation.id);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<String>():
        ref.invalidate(myGroupInvitationsProvider);
        if (accept) ref.invalidate(myGroupsProvider);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'انضممت إلى دوري «${invitation.groupName}».'
                  : 'رفضت الدعوة.',
            ),
          ),
        );
      case Err<String>():
        messenger?.showSnackBar(
          const SnackBar(
            key: Key('groupInvite.error'),
            content: Text('تعذّر إرسال ردّك. حاول مرة أخرى.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final GroupInvitationDto? invitation = ref
        .watch(myGroupInvitationsProvider)
        .value
        ?.forGroup(widget.groupId);
    if (invitation == null) return const SizedBox.shrink();
    final String id = invitation.id;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${invitation.inviterName} يدعوك إلى دوري «${invitation.groupName}».',
            key: Key('groupInvite.text.$id'),
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: AppFontSize.s13,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (invitation.isPending)
            Row(
              children: <Widget>[
                FilledButton(
                  key: Key('groupInvite.accept.$id'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_answer(invitation, true)),
                  child: const Text('قبول'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  key: Key('groupInvite.decline.$id'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_answer(invitation, false)),
                  child: const Text('رفض'),
                ),
              ],
            )
          else
            Text(
              invitation.status == 'accepted'
                  ? 'انضممت إلى الدوري.'
                  : 'رفضت الدعوة.',
              key: Key('groupInvite.answer.$id'),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: AppFontSize.s12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
