/// "الإعدادات" from the account tab: the account's records and groups,
/// which the redesigned account page no longer lists at the top level.
library;

import 'package:flutter/material.dart';

import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../groups/create_group_screen.dart';
import '../groups/join_group_screen.dart';
import '../groups/my_groups_screen.dart';
import '../record/my_seasons_screen.dart';
import '../record/season_record_screen.dart';
import 'widgets/account_menu.dart';

/// The settings page.
class AccountSettingsScreen extends StatelessWidget {
  /// Creates the page.
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;

    void open(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.accountSettings,
          key: const Key('accountSettings.title'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxAccountWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                AccountSectionTitle(l10n.accountRecordsSection),
                AccountMenuCard(
                  children: <Widget>[
                    AccountMenuRow(
                      key: const Key('account.seasonRecord'),
                      icon: Icons.emoji_events_outlined,
                      title: l10n.seasonRecord,
                      onTap: () => open(const SeasonRecordScreen()),
                    ),
                    AccountMenuRow(
                      key: const Key('account.mySeasons'),
                      icon: Icons.calendar_month_outlined,
                      title: l10n.mySeasonsLabel,
                      onTap: () => open(const MySeasonsScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                AccountSectionTitle(l10n.myGroups),
                AccountMenuCard(
                  children: <Widget>[
                    AccountMenuRow(
                      key: const Key('account.myGroups'),
                      icon: Icons.groups_outlined,
                      title: l10n.myGroups,
                      onTap: () => open(const MyGroupsScreen()),
                    ),
                    AccountMenuRow(
                      key: const Key('account.createGroup'),
                      icon: Icons.group_add_outlined,
                      title: l10n.createGroup,
                      onTap: () => open(const CreateGroupScreen()),
                    ),
                    AccountMenuRow(
                      key: const Key('account.joinGroup'),
                      icon: Icons.group_outlined,
                      title: l10n.joinGroup,
                      onTap: () => open(const JoinGroupScreen()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
