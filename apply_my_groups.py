#!/usr/bin/env python3
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent


def replace_once(path, old, new, marker=None):
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    if marker and marker in text:
        print(f"SKIP (already applied): {path}")
        return
    if old not in text:
        raise SystemExit(f"OLD STRING NOT FOUND in {path}")
    if text.count(old) != 1:
        raise SystemExit(f"OLD STRING NOT UNIQUE in {path}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"OK: {path}")


def create_new(path, content):
    p = ROOT / path
    if p.exists():
        print(f"SKIP (exists): {path}")
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    print(f"CREATED: {path}")


# 1) api_client: myGroups()
replace_once(
    "packages/api_client/lib/src/groups_api.dart",
    "  /// `GET /groups/{groupId}` \u2014 reads the group, visible only to a member.\n"
    "  Future<Result<GroupDto>> getGroup(String groupId) {",
    "  /// `GET /me/groups` \u2014 lists every group the caller belongs to.\n"
    "  Future<Result<MyGroupsDto>> myGroups() {\n"
    "    return _transport.getObject<MyGroupsDto>(\n"
    "      '/me/groups',\n"
    "      parse: MyGroupsDto.fromJson,\n"
    "    );\n"
    "  }\n\n"
    "  /// `GET /groups/{groupId}` \u2014 reads the group, visible only to a member.\n"
    "  Future<Result<GroupDto>> getGroup(String groupId) {",
    marker="Future<Result<MyGroupsDto>> myGroups()",
)

# 2) groups_providers.dart: myGroupsProvider
replace_once(
    "apps/mobile/lib/features/groups/groups_providers.dart",
    "/// Owns the `POST /groups` create command.",
    "/// `GET /me/groups` \u2014 every group the caller belongs to.\n"
    "@riverpod\n"
    "Future<MyGroupsDto> myGroups(Ref ref) async {\n"
    "  final api = ref.watch(groupsApiProvider);\n"
    "  return _unwrap(await api.myGroups());\n"
    "}\n\n"
    "/// Owns the `POST /groups` create command.",
    marker="Future<MyGroupsDto> myGroups(Ref ref)",
)

# 3) account_screen.dart: import + button
replace_once(
    "apps/mobile/lib/features/auth/account_screen.dart",
    "import '../groups/create_group_screen.dart';",
    "import '../groups/create_group_screen.dart';\n"
    "import '../groups/my_groups_screen.dart';",
    marker="import '../groups/my_groups_screen.dart';",
)

replace_once(
    "apps/mobile/lib/features/auth/account_screen.dart",
    "                  const SizedBox(height: AppSpacing.md),\n"
    "                  AppButton(\n"
    "                    key: const Key('account.createGroup'),",
    "                  const SizedBox(height: AppSpacing.md),\n"
    "                  AppButton(\n"
    "                    key: const Key('account.myGroups'),\n"
    "                    label: l10n.myGroups,\n"
    "                    icon: Icons.groups_outlined,\n"
    "                    variant: AppButtonVariant.secondary,\n"
    "                    onPressed: () => Navigator.of(context).push(\n"
    "                      MaterialPageRoute<void>(\n"
    "                        builder: (_) => const MyGroupsScreen(),\n"
    "                      ),\n"
    "                    ),\n"
    "                  ),\n"
    "                  const SizedBox(height: AppSpacing.md),\n"
    "                  AppButton(\n"
    "                    key: const Key('account.createGroup'),",
    marker="const Key('account.myGroups')",
)

# 4) app_ar.arb
replace_once(
    "apps/mobile/lib/l10n/app_ar.arb",
    '  "createGroupTitle": "\u0625\u0646\u0634\u0627\u0621 \u0645\u062c\u0645\u0648\u0639\u0629",',
    '  "myGroups": "\u0645\u062c\u0645\u0648\u0639\u0627\u062a\u064a",\n'
    '  "myGroupsEmpty": "\u0644\u0645 \u062a\u0646\u0636\u0645 \u0625\u0644\u0649 \u0623\u064a \u0645\u062c\u0645\u0648\u0639\u0629 \u0628\u0639\u062f.",\n'
    '  "groupRoleOwner": "\u0645\u0627\u0644\u0643",\n'
    '  "groupRoleMember": "\u0639\u0636\u0648",\n'
    '  "groupMemberCount": "{count, plural, zero{\u0644\u0627 \u064a\u0648\u062c\u062f \u0623\u0639\u0636\u0627\u0621} one{\u0639\u0636\u0648 \u0648\u0627\u062d\u062f} two{\u0639\u0636\u0648\u0627\u0646} few{{count} \u0623\u0639\u0636\u0627\u0621} many{{count} \u0639\u0636\u0648\u064b\u0627} other{{count} \u0639\u0636\u0648}}",\n'
    '  "createGroupTitle": "\u0625\u0646\u0634\u0627\u0621 \u0645\u062c\u0645\u0648\u0639\u0629",',
    marker='"myGroups": "',
)

# 5) app_en.arb
replace_once(
    "apps/mobile/lib/l10n/app_en.arb",
    '  "createGroupTitle": "Create Group",',
    '  "myGroups": "My Groups",\n'
    '  "myGroupsEmpty": "You haven\'t joined any group yet.",\n'
    '  "groupRoleOwner": "Owner",\n'
    '  "groupRoleMember": "Member",\n'
    '  "groupMemberCount": "{count, plural, =0{No members} =1{1 member} other{{count} members}}",\n'
    '  "@groupMemberCount": {\n'
    '    "placeholders": {\n'
    '      "count": {\n'
    '        "type": "int"\n'
    '      }\n'
    '    }\n'
    '  },\n'
    '  "createGroupTitle": "Create Group",',
    marker='"myGroups": "My Groups"',
)

# 6) app_localizations.dart (abstract getters)
replace_once(
    "apps/mobile/lib/l10n/app_localizations.dart",
    "  /// No description provided for @createGroupTitle.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'Create Group'**\n"
    "  String get createGroupTitle;",
    "  /// No description provided for @myGroups.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'My Groups'**\n"
    "  String get myGroups;\n\n"
    "  /// No description provided for @myGroupsEmpty.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'You haven\\'t joined any group yet.'**\n"
    "  String get myGroupsEmpty;\n\n"
    "  /// No description provided for @groupRoleOwner.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'Owner'**\n"
    "  String get groupRoleOwner;\n\n"
    "  /// No description provided for @groupRoleMember.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'Member'**\n"
    "  String get groupRoleMember;\n\n"
    "  /// No description provided for @groupMemberCount.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'{count, plural, =0{No members} =1{1 member} other{{count} members}}'**\n"
    "  String groupMemberCount(int count);\n\n"
    "  /// No description provided for @createGroupTitle.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'Create Group'**\n"
    "  String get createGroupTitle;",
    marker="String get myGroups;",
)

# 7) app_localizations_ar.dart
replace_once(
    "apps/mobile/lib/l10n/app_localizations_ar.dart",
    "  @override\n"
    "  String get createGroupTitle => '\u0625\u0646\u0634\u0627\u0621 \u0645\u062c\u0645\u0648\u0639\u0629';",
    "  @override\n"
    "  String get myGroups => '\u0645\u062c\u0645\u0648\u0639\u0627\u062a\u064a';\n\n"
    "  @override\n"
    "  String get myGroupsEmpty => '\u0644\u0645 \u062a\u0646\u0636\u0645 \u0625\u0644\u0649 \u0623\u064a \u0645\u062c\u0645\u0648\u0639\u0629 \u0628\u0639\u062f.';\n\n"
    "  @override\n"
    "  String get groupRoleOwner => '\u0645\u0627\u0644\u0643';\n\n"
    "  @override\n"
    "  String get groupRoleMember => '\u0639\u0636\u0648';\n\n"
    "  @override\n"
    "  String groupMemberCount(int count) {\n"
    "    String _temp0 = intl.Intl.pluralLogic(\n"
    "      count,\n"
    "      locale: localeName,\n"
    "      other: '$count \u0639\u0636\u0648',\n"
    "      many: '$count \u0639\u0636\u0648\u064b\u0627',\n"
    "      few: '$count \u0623\u0639\u0636\u0627\u0621',\n"
    "      two: '\u0639\u0636\u0648\u0627\u0646',\n"
    "      one: '\u0639\u0636\u0648 \u0648\u0627\u062d\u062f',\n"
    "      zero: '\u0644\u0627 \u064a\u0648\u062c\u062f \u0623\u0639\u0636\u0627\u0621',\n"
    "    );\n"
    "    return _temp0;\n"
    "  }\n\n"
    "  @override\n"
    "  String get createGroupTitle => '\u0625\u0646\u0634\u0627\u0621 \u0645\u062c\u0645\u0648\u0639\u0629';",
    marker="String get myGroups => '",
)

# 8) app_localizations_en.dart
replace_once(
    "apps/mobile/lib/l10n/app_localizations_en.dart",
    "  @override\n"
    "  String get createGroupTitle => 'Create Group';",
    "  @override\n"
    "  String get myGroups => 'My Groups';\n\n"
    "  @override\n"
    "  String get myGroupsEmpty => 'You haven\\'t joined any group yet.';\n\n"
    "  @override\n"
    "  String get groupRoleOwner => 'Owner';\n\n"
    "  @override\n"
    "  String get groupRoleMember => 'Member';\n\n"
    "  @override\n"
    "  String groupMemberCount(int count) {\n"
    "    String _temp0 = intl.Intl.pluralLogic(\n"
    "      count,\n"
    "      locale: localeName,\n"
    "      other: '$count members',\n"
    "      one: '1 member',\n"
    "      zero: 'No members',\n"
    "    );\n"
    "    return _temp0;\n"
    "  }\n\n"
    "  @override\n"
    "  String get createGroupTitle => 'Create Group';",
    marker="String get myGroups => 'My Groups';",
)

# 9) new screen file
create_new(
    "apps/mobile/lib/features/groups/my_groups_screen.dart",
    '''library;

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
''',
)

print("\nDONE.")
