/// سجل النقاط (الدفعة 146ب، البندان C-01 وL-14): المشرف يختار الشهر ثم
/// اللاعب باسمه، فيرى كل حركة في نقاطه ذلك الشهر مع المباراة، ونقاط الشهر
/// كما تحسبها اللوحة، ومكافآت السلسلة منفصلة (للدوري الأسبوعي وحده).
///
/// كان القسم يطلب معرّف مشاركة يُكتب يدويًا، ويقرأ دفتر الجولات القديم
/// (`ledger.point_entries`) الفارغ منذ صارت النقاط للمباريات، فلا يظهر لأي
/// لاعب حالي شيء. القراءة الآن من `ledger.fixture_point_entries`
/// (`GET /admin/users/{id}/points`)، وتُكتب في سجل التدقيق كما كانت.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../../../core/ui/ui.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// A ledger entry kind in words.
String pointEntryKindLabel(String kind) => switch (kind) {
  'fixture_score' => 'نقاط المباراة',
  'correction' => 'تصحيح',
  'streak_bonus' => 'مكافأة سلسلة (الدوري الأسبوعي)',
  'round_score' => 'نقاط جولة',
  _ => kind,
};

class LedgerLookupSection extends ConsumerStatefulWidget {
  const LedgerLookupSection({super.key});

  @override
  ConsumerState<LedgerLookupSection> createState() =>
      _LedgerLookupSectionState();
}

class _LedgerLookupSectionState extends ConsumerState<LedgerLookupSection> {
  final TextEditingController _searchController = TextEditingController();

  String? _seasonId;
  UserSummaryDto? _player;
  AsyncValue<List<UserSummaryDto>>? _found;
  AsyncValue<PlayerMonthPointsDto>? _points;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String term = _searchController.text.trim();
    if (term.isEmpty) return;
    setState(() => _found = const AsyncLoading<List<UserSummaryDto>>());
    final Result<UserListDto> result = await ref
        .read(adminApiProvider)
        .listUsers(search: term);
    if (!mounted) return;
    setState(() {
      _found = switch (result) {
        Ok<UserListDto>(:final value) => AsyncData<List<UserSummaryDto>>(
          value.users,
        ),
        Err<UserListDto>(:final error) => AsyncError<List<UserSummaryDto>>(
          error,
          StackTrace.current,
        ),
      };
    });
  }

  Future<void> _load() async {
    final UserSummaryDto? player = _player;
    final String? seasonId = _seasonId;
    if (player == null || seasonId == null) return;
    setState(() => _points = const AsyncLoading<PlayerMonthPointsDto>());
    final Result<PlayerMonthPointsDto> result = await ref
        .read(adminApiProvider)
        .playerPoints(player.id, seasonId: seasonId);
    if (!mounted) return;
    setState(() {
      _points = switch (result) {
        Ok<PlayerMonthPointsDto>(:final value) =>
          AsyncData<PlayerMonthPointsDto>(value),
        Err<PlayerMonthPointsDto>(:final error) =>
          AsyncError<PlayerMonthPointsDto>(error, StackTrace.current),
      };
    });
    // The read left a line in the audit log.
    ref.invalidate(auditLogProvider);
  }

  static String _nameOf(UserSummaryDto user) =>
      user.displayName.isEmpty ? (user.email ?? 'لاعب') : user.displayName;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final UserSummaryDto? player = _player;
    final AsyncValue<List<UserSummaryDto>>? found = _found;
    final AsyncValue<PlayerMonthPointsDto>? points = _points;
    final bool searching = found is AsyncLoading<List<UserSummaryDto>>;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'سجل النقاط',
          subtitle:
              'اختر الشهر ثم اللاعب لترى كل حركة في نقاطه مع المباراة. '
              'كل اطّلاع يُكتب في سجل التدقيق.',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MonthPickerField(
                key: const Key('admin.ledger.monthField'),
                enabled: true,
                selectedId: _seasonId,
                onSelected: (SeasonDto month) {
                  setState(() => _seasonId = month.id);
                  unawaited(_load());
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: AdminTextField(
                      key: const Key('admin.ledger.searchField'),
                      controller: _searchController,
                      hint: 'ابحث باسم اللاعب',
                      prefixIcon: Icons.search_rounded,
                      enabled: !searching,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 100,
                    child: AppButton(
                      key: const Key('admin.ledger.search'),
                      label: 'بحث',
                      loading: searching,
                      onPressed: searching ? null : _search,
                    ),
                  ),
                ],
              ),
              if (found is AsyncError<List<UserSummaryDto>>) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  ErrorPresenter.messageOf(found.error),
                  style: TextStyle(color: tokens.errorText),
                ),
              ],
              if (found is AsyncData<List<UserSummaryDto>>) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                if (found.value.isEmpty)
                  const Text('لا يوجد لاعبون بهذا الاسم.')
                else
                  for (final UserSummaryDto user in found.value)
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        key: Key('admin.ledger.user.${user.id}'),
                        contentPadding: EdgeInsets.zero,
                        selected: user.id == player?.id,
                        leading: const Icon(Icons.person_rounded),
                        title: Text(_nameOf(user)),
                        onTap: () {
                          setState(() {
                            _player = user;
                            _found = null;
                            _points = null;
                          });
                          unawaited(_load());
                        },
                      ),
                    ),
              ],
              if (player != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _nameOf(player),
                  key: const Key('admin.ledger.player'),
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_seasonId == null)
                  Text(
                    'اختر الشهر.',
                    style: TextStyle(color: tokens.textMuted),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (points is AsyncLoading<PlayerMonthPointsDto>)
          const Center(child: CircularProgressIndicator()),
        if (points is AsyncError<PlayerMonthPointsDto>)
          AdminErrorBanner(
            key: const Key('admin.ledger.error'),
            message: ErrorPresenter.messageOf(points.error),
          ),
        if (points is AsyncError<PlayerMonthPointsDto>)
          AdminSecondaryButton(
            key: const Key('admin.ledger.retry'),
            label: 'إعادة المحاولة',
            icon: Icons.refresh_rounded,
            onPressed: _load,
          ),
        if (points is AsyncData<PlayerMonthPointsDto>)
          ..._month(context, points.value),
      ],
    );
  }

  List<Widget> _month(BuildContext context, PlayerMonthPointsDto month) {
    final AppTokens tokens = context.tokens;
    if (!month.played) {
      return const <Widget>[
        AdminCard(
          key: Key('admin.ledger.notPlayed'),
          child: AdminEmptyState(
            icon: Icons.event_busy_rounded,
            title: 'لم يلعب في هذا الشهر.',
          ),
        ),
      ];
    }
    return <Widget>[
      AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'نقاط الشهر: ${month.monthPoints}',
              key: const Key('admin.ledger.monthPoints'),
              style: context.text.titleMedium,
            ),
            if (month.streakBonus != 0)
              Text(
                'مكافآت السلسلة (للدوري الأسبوعي فقط): ${month.streakBonus}',
                key: const Key('admin.ledger.streakBonus'),
                style: TextStyle(color: tokens.textSecondary),
              ),
            if (month.entries.isEmpty)
              Text(
                'لا حركة في نقاطه بعد.',
                style: TextStyle(color: tokens.textMuted),
              ),
          ],
        ),
      ),
      for (final PlayerPointEntryDto entry in month.entries) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        AdminCard(
          key: Key('admin.ledger.item.${entry.id}'),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.homeTeam == null || entry.awayTeam == null
                          ? 'مباراة'
                          : '${entry.homeTeam} × ${entry.awayTeam}',
                      key: Key('admin.ledger.match.${entry.id}'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${pointEntryKindLabel(entry.kind)} · '
                      '${formatTimestamp(context, entry.occurredAt)}',
                      key: Key('admin.ledger.kind.${entry.id}'),
                      style: TextStyle(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                entry.amount > 0 ? '+${entry.amount}' : '${entry.amount}',
                key: Key('admin.ledger.amount.${entry.id}'),
                style: context.text.titleSmall,
              ),
            ],
          ),
        ),
      ],
    ];
  }
}
