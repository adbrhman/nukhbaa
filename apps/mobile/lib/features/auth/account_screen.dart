library;

import 'dart:async';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../admin/admin_dashboard_screen.dart';
import '../competition/competition_list_screen.dart';
import '../groups/create_group_screen.dart';
import '../groups/join_group_screen.dart';
import '../hall_of_fame/hall_of_fame_screen.dart';
import '../history/prediction_history_screen.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import 'session_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({required this.user, super.key});
  final AuthenticatedUserDto user;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> unread = ref.watch(unreadCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nukhba'),
        actions: <Widget>[
          IconButton(
            key: const Key('account.notifications'),
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
            icon: Badge(
              key: const Key('account.notifications.badge'),
              label: unread.maybeWhen(
                data: (count) => count > 0 ? Text('$count') : null,
                orElse: () => null,
              ),
              isLabelVisible: unread.maybeWhen(
                data: (count) => count > 0,
                orElse: () => false,
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            key: const Key('account.signOut'),
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => unawaited(
              ref.read(sessionControllerProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Signed in',
                    key: Key('account.title'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Field(
                    label: 'User ID',
                    value: user.userId,
                    valueKey: const Key('account.userId'),
                  ),
                  _Field(
                    label: 'Role',
                    value: user.role,
                    valueKey: const Key('account.role'),
                  ),
                  _Field(
                    label: 'Status',
                    value: user.status,
                    valueKey: const Key('account.status'),
                  ),
                  if (user.email != null)
                    _Field(
                      label: 'Email',
                      value: user.email!,
                      valueKey: const Key('account.email'),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('account.browseCompetitions'),
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: const Text('Browse competitions'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CompetitionListScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('account.hallOfFame'),
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: const Text('Hall of Fame'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HallOfFameScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('account.myPredictions'),
                    icon: const Icon(Icons.history_outlined),
                    label: const Text('My Predictions'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PredictionHistoryScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('account.createGroup'),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Create a group'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CreateGroupScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('account.joinGroup'),
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Join a group'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const JoinGroupScreen(),
                      ),
                    ),
                  ),
                  // The true authority gate is server-side inside every AdminApi
                  // call; this conditional only decides whether the entry point is
                  // offered to the caller.
                  if (user.role == 'admin') ...<Widget>[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('account.adminDashboard'),
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Admin dashboard'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminDashboardScreen(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.valueKey,
  });
  final String label;
  final String value;
  final Key valueKey;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              value,
              key: valueKey,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
