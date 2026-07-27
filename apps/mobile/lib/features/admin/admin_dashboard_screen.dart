library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/error/error_presenter.dart';
import '../../core/theme/app_colors.dart';
import '../competition/widgets/async_list_view.dart';
import 'admin_providers.dart';

/// The admin dashboard. Gated by the caller's platform role — a route pushing
/// this screen must first check `AuthenticatedUserDto.role == 'admin'`
/// (`AccountScreen` does this before offering the entry point); the true
/// authority gate is still server-side inside every `AdminApi` call.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin', key: Key('admin.title')),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(key: Key('admin.tab.audit'), text: 'Audit Log'),
              Tab(key: Key('admin.tab.users'), text: 'Users'),
              Tab(key: Key('admin.tab.ledger'), text: 'Ledger Lookup'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _AuditLogTab(),
            _UserSanctionTab(),
            _LedgerLookupTab(),
          ],
        ),
      ),
    );
  }
}

class _AuditLogTab extends ConsumerWidget {
  const _AuditLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AuditLogDto> log = ref.watch(auditLogProvider);
    return AsyncListView<AuditEntryDto>(
      value: log.whenData((dto) => dto.entries),
      emptyMessage: 'No audit entries yet.',
      onRetry: () => ref.invalidate(auditLogProvider),
      itemBuilder: (context, entry) => ListTile(
        key: Key('admin.audit.item.${entry.id}'),
        title: Text(entry.action, key: Key('admin.audit.action.${entry.id}')),
        subtitle: Text(
          '${entry.targetRef}${entry.reason != null ? ' — ${entry.reason}' : ''}',
          key: Key('admin.audit.detail.${entry.id}'),
        ),
        trailing: Text(
          entry.occurredAt,
          key: Key('admin.audit.occurredAt.${entry.id}'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _UserSanctionTab extends ConsumerStatefulWidget {
  const _UserSanctionTab();

  @override
  ConsumerState<_UserSanctionTab> createState() => _UserSanctionTabState();
}

class _UserSanctionTabState extends ConsumerState<_UserSanctionTab> {
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<UserSanctionResultDto>? state = ref.watch(
      userSanctionControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<UserSanctionResultDto>;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('admin.users.userIdField'),
            controller: _userIdController,
            decoration: const InputDecoration(
              labelText: 'User ID',
              border: OutlineInputBorder(),
            ),
            enabled: !inFlight,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('admin.users.reasonField'),
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason (mandatory)',
              border: OutlineInputBorder(),
            ),
            enabled: !inFlight,
          ),
          const SizedBox(height: 16),
          if (state is AsyncError<UserSanctionResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                ErrorPresenter.message(state.error as AppError),
                key: const Key('admin.users.error'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          if (state is AsyncData<UserSanctionResultDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${state.value.userId} is now ${state.value.status}',
                key: const Key('admin.users.result'),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: const Key('admin.users.suspend'),
                  onPressed: inFlight ? null : () => _act(suspend: true),
                  child: const Text('Suspend'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('admin.users.reinstate'),
                  onPressed: inFlight ? null : () => _act(suspend: false),
                  child: const Text('Reinstate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _act({required bool suspend}) {
    final userId = _userIdController.text.trim();
    final reason = _reasonController.text.trim();
    if (userId.isEmpty || reason.isEmpty) return;
    final notifier = ref.read(userSanctionControllerProvider.notifier);
    if (suspend) {
      notifier.suspend(userId, reason);
    } else {
      notifier.reinstate(userId, reason);
    }
  }
}

class _LedgerLookupTab extends ConsumerStatefulWidget {
  const _LedgerLookupTab();

  @override
  ConsumerState<_LedgerLookupTab> createState() => _LedgerLookupTabState();
}

class _LedgerLookupTabState extends ConsumerState<_LedgerLookupTab> {
  final TextEditingController _participantIdController =
      TextEditingController();

  @override
  void dispose() {
    _participantIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ParticipantEntriesDto>? state = ref.watch(
      adminLedgerLookupControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<ParticipantEntriesDto>;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('admin.ledger.participantIdField'),
                  controller: _participantIdController,
                  decoration: const InputDecoration(
                    labelText: 'Participant ID',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !inFlight,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: const Key('admin.ledger.lookup'),
                onPressed: inFlight
                    ? null
                    : () {
                        final id = _participantIdController.text.trim();
                        if (id.isEmpty) return;
                        ref
                            .read(adminLedgerLookupControllerProvider.notifier)
                            .lookup(id);
                      },
                child: const Text('Look up'),
              ),
            ],
          ),
        ),
        if (state is AsyncLoading<ParticipantEntriesDto>)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        if (state is AsyncError<ParticipantEntriesDto>)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              ErrorPresenter.message(state.error as AppError),
              key: const Key('admin.ledger.error'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (state is AsyncData<ParticipantEntriesDto>)
          Expanded(
            child: ListView.separated(
              key: const Key('admin.ledger.list'),
              itemCount: state.value.entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = state.value.entries[index];
                return ListTile(
                  key: Key('admin.ledger.item.${entry.id}'),
                  title: Text(
                    entry.kind,
                    key: Key('admin.ledger.kind.${entry.id}'),
                  ),
                  subtitle: Text(
                    entry.occurredAt,
                    key: Key('admin.ledger.occurredAt.${entry.id}'),
                  ),
                  trailing: Text(
                    '${entry.amount}',
                    key: Key('admin.ledger.amount.${entry.id}'),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
