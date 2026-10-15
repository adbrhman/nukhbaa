/// A friends' league's members, and the ways out of it (audit M-26, batch
/// 141): the owner removes a member or deletes the league, a member leaves.
/// Every gate is the server's; this screen only asks before acting and
/// says what happened.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/analytics/screen_views.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/providers.dart';
import '../competition/widgets/async_list_view.dart';
import 'groups_providers.dart';
import 'league_invite_sheet.dart';

/// The members of [group]; [isOwner] is the viewer's own role in it.
class GroupMembersScreen extends ConsumerStatefulWidget implements NamedScreen {
  @override
  String get screenName => ScreenNames.groups;

  /// Creates the screen.
  const GroupMembersScreen({
    required this.group,
    required this.isOwner,
    super.key,
  });

  /// The league.
  final GroupDto group;

  /// Whether the viewer owns it.
  final bool isOwner;

  @override
  ConsumerState<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends ConsumerState<GroupMembersScreen> {
  bool _busy = false;

  Future<bool> _confirm(String title, String body, String action) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            key: const Key('groupMembers.confirm.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('groupMembers.confirm.ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  /// Runs [call]; on success says [done] and refreshes the league lists,
  /// leaving the screen when [leave]; on failure says why.
  Future<void> _run(
    Future<Result<bool>> Function(GroupsApi api) call, {
    required String done,
    required bool leave,
  }) async {
    setState(() => _busy = true);
    final Result<bool> result = await call(ref.read(groupsApiProvider));
    if (!mounted) return;
    setState(() => _busy = false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case Ok<bool>():
        ref.invalidate(myGroupsProvider);
        ref.invalidate(groupMembersProvider(widget.group.id));
        messenger.showSnackBar(SnackBar(content: Text(done)));
        if (leave) Navigator.of(context).pop(true);
      case Err<bool>(:final error):
        messenger.showSnackBar(
          SnackBar(content: Text(ErrorPresenter.message(error))),
        );
    }
  }

  Future<void> _remove(GroupMembershipDto member) async {
    final String name = member.displayName ?? 'هذا العضو';
    if (!await _confirm(
      'إخراج $name؟',
      'سيخرج من الدوري ولن يظهر في ترتيبه. يستطيع الانضمام مجدداً إن بقي '
          'معه الرمز، فغيّر الرمز إن لم ترد ذلك.',
      'أخرِجه',
    )) {
      return;
    }
    await _run(
      (api) => api.removeMember(widget.group.id, member.userId),
      done: 'أُخرج $name من الدوري.',
      leave: false,
    );
  }

  Future<void> _leave() async {
    if (!await _confirm(
      'مغادرة «${widget.group.name}»؟',
      'لن يظهر اسمك في ترتيب الدوري ولا تصلك إشعاراته. نقاطك في المسابقة '
          'لا تتغير.',
      'غادِر',
    )) {
      return;
    }
    await _run(
      (api) => api.leaveGroup(widget.group.id),
      done: 'غادرت «${widget.group.name}».',
      leave: true,
    );
  }

  Future<void> _delete() async {
    if (!await _confirm(
      'حذف «${widget.group.name}»؟',
      'يُحذف الدوري لكل أعضائه ولا يمكن التراجع. نقاط الأعضاء في المسابقة '
          'لا تتغير.',
      'احذفه',
    )) {
      return;
    }
    await _run(
      (api) => api.deleteGroup(widget.group.id),
      done: 'حُذف «${widget.group.name}».',
      leave: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<GroupMembersDto> members = ref.watch(
      groupMembersProvider(widget.group.id),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'أعضاء «${widget.group.name}»',
          key: const Key('groupMembers.title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('groupMembers.invite'),
            tooltip: 'ادعُ',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () =>
                unawaited(showLeagueInviteSheet(context, widget.group)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: AsyncListView<GroupMembershipDto>(
              value: members.whenData((dto) => dto.members),
              emptyMessage: 'لا أعضاء في هذا الدوري.',
              onRetry: () =>
                  ref.invalidate(groupMembersProvider(widget.group.id)),
              itemBuilder: (context, member) {
                final bool owner = member.role == 'owner';
                return ListTile(
                  key: Key('groupMembers.item.${member.userId}'),
                  leading: Icon(
                    owner
                        ? Icons.workspace_premium_rounded
                        : Icons.person_outline_rounded,
                    color: owner ? tokens.primary : tokens.textSecondary,
                  ),
                  title: Text(
                    member.displayName ?? 'عضو',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: owner ? const Text('المالك') : null,
                  trailing: widget.isOwner && !owner
                      ? IconButton(
                          key: Key('groupMembers.remove.${member.userId}'),
                          tooltip: 'أخرِجه من الدوري',
                          icon: Icon(
                            Icons.person_remove_alt_1_rounded,
                            color: tokens.error,
                          ),
                          onPressed: _busy
                              ? null
                              : () => unawaited(_remove(member)),
                        )
                      : null,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: widget.isOwner
                  ? OutlinedButton.icon(
                      key: const Key('groupMembers.delete'),
                      onPressed: _busy ? null : () => unawaited(_delete()),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: tokens.error,
                      ),
                      label: Text(
                        'حذف الدوري',
                        style: TextStyle(color: tokens.errorText),
                      ),
                    )
                  : OutlinedButton.icon(
                      key: const Key('groupMembers.leave'),
                      onPressed: _busy ? null : () => unawaited(_leave()),
                      icon: Icon(Icons.logout_rounded, color: tokens.error),
                      label: Text(
                        'مغادرة الدوري',
                        style: TextStyle(color: tokens.errorText),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
