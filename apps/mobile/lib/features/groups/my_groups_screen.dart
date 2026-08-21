library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_card.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'group_feed_screen.dart';
import 'groups_providers.dart';

/// Lists every group the caller belongs to (`GET /me/groups`), each row
/// carrying its invite code (a capability the caller already holds as a
/// member) so it can be re-shared without going through group creation
/// again. Tapping a row opens that group's activity feed.
class MyGroupsScreen extends ConsumerWidget {
  const MyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<MyGroupsDto> myGroups = ref.watch(myGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myGroups, key: const Key('myGroups.title')),
      ),
      body: AsyncListView<MyGroupEntryDto>(
        value: myGroups.whenData((dto) => dto.groups),
        emptyMessage: l10n.myGroupsEmpty,
        onRetry: () => ref.invalidate(myGroupsProvider),
        itemBuilder: (context, entry) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: _GroupRow(entry: entry),
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.entry});

  final MyGroupEntryDto entry;

  Future<void> _copyInviteCode(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: entry.group.inviteCode));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.inviteCodeCopiedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupFeedScreen(
            groupId: entry.group.id,
            groupName: entry.group.name,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.group.name,
                  key: const Key('myGroups.item.name'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _RoleBadge(role: entry.role, tokens: tokens),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.groupMemberCount(entry.group.memberCount),
            style: TextStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Icon(
                Icons.vpn_key_outlined,
                size: AppSizes.iconSm,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                entry.group.inviteCode,
                key: const Key('myGroups.item.inviteCode'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: tokens.primary,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const Key('myGroups.item.copyButton'),
                icon: Icon(Icons.copy_outlined, color: tokens.primary),
                tooltip: l10n.copyInviteCodeButton,
                onPressed: () => _copyInviteCode(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, required this.tokens});

  final String role;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isOwner = role == 'owner';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isOwner
            ? tokens.primary.withValues(alpha: 0.12)
            : tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSizes.iconSm),
      ),
      child: Text(
        isOwner ? l10n.groupRoleOwner : l10n.groupRoleMember,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isOwner ? tokens.primary : tokens.textSecondary,
        ),
      ),
    );
  }
}
