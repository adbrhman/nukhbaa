library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_typography.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/ui/ui.dart';
import '../../../../l10n/app_localizations.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_ui_kit.dart';

class UserSanctionSection extends ConsumerStatefulWidget {
  const UserSanctionSection({super.key});

  @override
  ConsumerState<UserSanctionSection> createState() =>
      _UserSanctionSectionState();
}

class _UserSanctionSectionState extends ConsumerState<UserSanctionSection> {
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  UserSummaryDto? _selectedUser;
  AdminUserPredictionFilter _filter = AdminUserPredictionFilter.today;
  DateTime? _selectedDate;

  @override
  void dispose() {
    _userIdController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _selectUser(UserSummaryDto user) {
    setState(() {
      _selectedUser = user;
      _userIdController.text = user.id;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(2026),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _filter = AdminUserPredictionFilter.date;
      _selectedDate = picked;
    });
  }

  ({DateTime? fromUtc, DateTime? toUtc}) _range() {
    final now = DateTime.now();
    late final DateTime start;
    late final DateTime end;
    switch (_filter) {
      case AdminUserPredictionFilter.today:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
      case AdminUserPredictionFilter.yesterday:
        end = DateTime(now.year, now.month, now.day);
        start = end.subtract(const Duration(days: 1));
      case AdminUserPredictionFilter.date:
        final selected = _selectedDate ?? now;
        start = DateTime(selected.year, selected.month, selected.day);
        end = start.add(const Duration(days: 1));
      case AdminUserPredictionFilter.all:
        return (fromUtc: null, toUtc: null);
    }
    return (fromUtc: start.toUtc(), toUtc: end.toUtc());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<UserSanctionResultDto>? sanctionState = ref.watch(
      userSanctionControllerProvider,
    );
    final bool sanctionInFlight =
        sanctionState is AsyncLoading<UserSanctionResultDto>;
    final AppTokens tokens = context.tokens;
    final user = _selectedUser;
    final range = _range();
    final query = user == null
        ? null
        : AdminUserPredictionQuery(
            userId: user.id,
            fromUtc: range.fromUtc,
            toUtc: range.toUtc,
          );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'بحث عن مستخدم وتوقعاته',
          subtitle: 'اختر مستخدمًا لعرض توقعاته هو فقط ونتائج تقييمها.',
        ),
        _UserPredictionSearchCard(
          selectedUserId: user?.id,
          onSelected: _selectUser,
        ),
        if (user != null && query != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SelectedUserSummary(user: user),
          const SizedBox(height: AppSpacing.md),
          _PredictionFilters(
            filter: _filter,
            selectedDate: _selectedDate,
            onFilterChanged: (filter) => setState(() => _filter = filter),
            onPickDate: _pickDate,
          ),
          const SizedBox(height: AppSpacing.md),
          _PredictionHistoryTable(query: query),
        ],
        const SizedBox(height: AppSpacing.xl),
        AdminSectionHeader(
          title: l10n.adminUsersTab,
          subtitle: 'إدارة تعليق المستخدمين وإعادة تفعيلهم.',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AdminTextField(
                key: const Key('admin.users.userIdField'),
                controller: _userIdController,
                hint: l10n.userId,
                enabled: !sanctionInFlight,
                prefixIcon: Icons.person_search_rounded,
              ),
              const SizedBox(height: AppSpacing.md),
              AdminTextField(
                key: const Key('admin.users.reasonField'),
                controller: _reasonController,
                hint: l10n.adminReasonMandatoryLabel,
                enabled: !sanctionInFlight,
                prefixIcon: Icons.notes_rounded,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (sanctionState is AsyncError<UserSanctionResultDto>)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    ErrorPresenter.message(sanctionState.error as AppError),
                    key: const Key('admin.users.error'),
                    style: TextStyle(color: tokens.error),
                  ),
                ),
              if (sanctionState is AsyncData<UserSanctionResultDto>)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    l10n.adminSanctionResultMessage(
                      sanctionState.value.userId,
                      sanctionState.value.status,
                    ),
                    key: const Key('admin.users.result'),
                  ),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppButton(
                      key: const Key('admin.users.suspend'),
                      label: l10n.adminSuspendButton,
                      variant: AppButtonVariant.secondary,
                      onPressed: sanctionInFlight
                          ? null
                          : () => _act(suspend: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      key: const Key('admin.users.reinstate'),
                      label: l10n.adminReinstateButton,
                      onPressed: sanctionInFlight
                          ? null
                          : () => _act(suspend: false),
                      loading: sanctionInFlight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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

enum AdminUserPredictionFilter { today, yesterday, all, date }

class _UserPredictionSearchCard extends ConsumerStatefulWidget {
  const _UserPredictionSearchCard({
    required this.selectedUserId,
    required this.onSelected,
  });

  final String? selectedUserId;
  final ValueChanged<UserSummaryDto> onSelected;

  @override
  ConsumerState<_UserPredictionSearchCard> createState() =>
      _UserPredictionSearchCardState();
}

class _UserPredictionSearchCardState
    extends ConsumerState<_UserPredictionSearchCard> {
  final TextEditingController _searchController = TextEditingController();

  void _search() {
    ref
        .read(usersLookupControllerProvider.notifier)
        .search(_searchController.text.trim());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(usersLookupControllerProvider);
    final tokens = context.tokens;
    final searching = search is AsyncLoading<UserListDto>;
    return AdminCard(
      key: const Key('admin.users.predictionSearch.card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: AdminTextField(
                  key: const Key('admin.users.predictionSearch.field'),
                  controller: _searchController,
                  hint: 'ابحث باسم المستخدم',
                  prefixIcon: Icons.search_rounded,
                  enabled: !searching,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 120,
                child: AppButton(
                  key: const Key('admin.users.predictionSearch.button'),
                  label: 'بحث',
                  onPressed: searching ? null : _search,
                  loading: searching,
                ),
              ),
            ],
          ),
          if (search != null) ...[
            const SizedBox(height: AppSpacing.md),
            search.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Text(
                ErrorPresenter.message(error as AppError),
                style: TextStyle(color: tokens.error),
              ),
              data: (dto) => dto.users.isEmpty
                  ? const Text('لا يوجد مستخدمون مطابقون.')
                  : Column(
                      children: [
                        for (final user in dto.users)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: ListTile(
                              key: Key(
                                'admin.users.predictionSearch.result.${user.id}',
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: tokens.border),
                              ),
                              tileColor: user.id == widget.selectedUserId
                                  ? tokens.primary.withValues(alpha: 0.08)
                                  : tokens.surfaceElevated,
                              leading: CircleAvatar(
                                backgroundColor: tokens.primary,
                                child: Text(
                                  user.displayName.isEmpty
                                      ? '؟'
                                      : user.displayName.substring(0, 1),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                user.displayName.isEmpty
                                    ? user.email ?? user.id
                                    : user.displayName,
                              ),
                              subtitle: Text(
                                user.email ?? user.id,
                                style: TextStyle(color: tokens.textSecondary),
                              ),
                              trailing: Text(
                                user.status,
                                style: TextStyle(color: tokens.textSecondary),
                              ),
                              onTap: () => widget.onSelected(user),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedUserSummary extends StatelessWidget {
  const _SelectedUserSummary({required this.user});

  final UserSummaryDto user;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AdminCard(
      key: const Key('admin.users.predictionSearch.summary'),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: tokens.primary,
            child: Text(
              user.displayName.isEmpty ? '؟' : user.displayName.substring(0, 1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppFontSize.s24,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.displayName.isEmpty
                      ? user.email ?? user.id
                      : user.displayName,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'المعرف: ${user.id}',
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Chip(
            label: Text(user.status),
            avatar: Icon(Icons.circle, size: 10, color: tokens.success),
          ),
        ],
      ),
    );
  }
}

class _PredictionFilters extends StatelessWidget {
  const _PredictionFilters({
    required this.filter,
    required this.selectedDate,
    required this.onFilterChanged,
    required this.onPickDate,
  });

  final AdminUserPredictionFilter filter;
  final DateTime? selectedDate;
  final ValueChanged<AdminUserPredictionFilter> onFilterChanged;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          _FilterButton(
            label: 'اليوم',
            selected: filter == AdminUserPredictionFilter.today,
            onPressed: () => onFilterChanged(AdminUserPredictionFilter.today),
          ),
          _FilterButton(
            label: 'أمس',
            selected: filter == AdminUserPredictionFilter.yesterday,
            onPressed: () =>
                onFilterChanged(AdminUserPredictionFilter.yesterday),
          ),
          _FilterButton(
            label: 'كل التوقعات',
            selected: filter == AdminUserPredictionFilter.all,
            onPressed: () => onFilterChanged(AdminUserPredictionFilter.all),
          ),
          _FilterButton(
            label: selectedDate == null
                ? 'اختيار تاريخ'
                : '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}',
            selected: filter == AdminUserPredictionFilter.date,
            onPressed: onPickDate,
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}

class _PredictionHistoryTable extends ConsumerWidget {
  const _PredictionHistoryTable({required this.query});

  final AdminUserPredictionQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminUserPredictionHistoryProvider(query));
    return state.when(
      loading: () => const AdminCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (error, _) => AdminCard(
        child: AdminErrorBanner(
          key: const Key('admin.users.predictionSearch.error'),
          message: ErrorPresenter.message(error as AppError),
        ),
      ),
      data: (history) => _HistoryData(history: history),
    );
  }
}

class _HistoryData extends StatelessWidget {
  const _HistoryData({required this.history});

  final AdminUserPredictionHistoryDto history;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: <Widget>[
            _StatCard(
              label: 'عدد التوقعات',
              value: '${history.predictionCount}',
              icon: Icons.rule_folder_rounded,
              color: tokens.primary,
            ),
            _StatCard(
              label: 'نتيجة دقيقة',
              value: '${history.exactCount}',
              icon: Icons.check_circle_rounded,
              color: tokens.success,
            ),
            _StatCard(
              label: 'دبل صحيح',
              value: '${history.correctDoubleCount}',
              icon: Icons.local_fire_department_rounded,
              color: tokens.gold,
            ),
            _StatCard(
              label: 'مجموع النقاط',
              value: '${history.totalPoints}',
              icon: Icons.emoji_events_rounded,
              color: tokens.primary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (history.predictions.isEmpty)
          const AdminCard(
            child: AdminEmptyState(
              icon: Icons.rule_folder_outlined,
              title: 'لا توجد توقعات ضمن الفلتر المحدد.',
            ),
          )
        else
          AdminCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('وقت المباراة')),
                  DataColumn(label: Text('الدوري')),
                  DataColumn(label: Text('المباراة')),
                  DataColumn(label: Text('توقع المستخدم')),
                  DataColumn(label: Text('النتيجة النهائية')),
                  DataColumn(label: Text('الحالة')),
                  DataColumn(label: Text('الدبل')),
                  DataColumn(label: Text('النقاط')),
                ],
                rows: [
                  for (var i = 0; i < history.predictions.length; i++)
                    _predictionRow(context, history.predictions[i], i + 1),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static DataRow _predictionRow(
    BuildContext context,
    AdminUserPredictionRowDto prediction,
    int index,
  ) {
    final tokens = context.tokens;
    final status = _statusFor(prediction);
    return DataRow(
      cells: <DataCell>[
        DataCell(Text('$index')),
        DataCell(Text(formatTimestamp(context, prediction.kickoffAt))),
        DataCell(Text(prediction.leagueName ?? '—')),
        DataCell(
          Text(
            '${prediction.homeTeam} × ${prediction.awayTeam}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataCell(
          Text(
            '${prediction.predictedHomeGoals} - ${prediction.predictedAwayGoals}',
            textDirection: TextDirection.ltr,
          ),
        ),
        DataCell(
          Text(
            prediction.finalHomeGoals == null ||
                    prediction.finalAwayGoals == null
                ? '—'
                : '${prediction.finalHomeGoals} - ${prediction.finalAwayGoals}',
            textDirection: TextDirection.ltr,
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(status.icon, size: 18, color: status.color(tokens)),
              const SizedBox(width: AppSpacing.xs),
              Text(status.label),
            ],
          ),
        ),
        DataCell(Text(prediction.isDouble ? '🔥' : '—')),
        DataCell(Text(prediction.points?.toString() ?? '—')),
      ],
    );
  }

  static _StatusInfo _statusFor(AdminUserPredictionRowDto prediction) {
    return switch (prediction.grade) {
      'exact_scoreline' =>
        prediction.isDouble
            ? const _StatusInfo(
                '🔥 دبل صحيح',
                Icons.local_fire_department_rounded,
                _gold,
              )
            : const _StatusInfo(
                '✅ نتيجة دقيقة',
                Icons.check_circle_rounded,
                _success,
              ),
      'correct_outcome' => const _StatusInfo(
        '✅ نتيجة صحيحة',
        Icons.check_circle_outline_rounded,
        _success,
      ),
      'incorrect' => const _StatusInfo(
        '❌ توقع خاطئ',
        Icons.cancel_rounded,
        _error,
      ),
      'pending' => const _StatusInfo(
        '⏳ بانتظار النتيجة',
        Icons.schedule_rounded,
        _secondary,
      ),
      'missed' => const _StatusInfo(
        '— لم يتوقع',
        Icons.remove_circle_outline_rounded,
        _secondary,
      ),
      _ => const _StatusInfo('—', Icons.help_outline_rounded, _secondary),
    };
  }

  static Color _gold(AppTokens t) => t.gold;
  static Color _success(AppTokens t) => t.success;
  static Color _error(AppTokens t) => t.error;
  static Color _secondary(AppTokens t) => t.textSecondary;
}

class _StatusInfo {
  const _StatusInfo(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color Function(AppTokens) color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: AdminCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value,
                    style: context.text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
