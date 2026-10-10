/// The tabs of the admin's head-to-head dashboard beyond the rounds
/// (batch 93): the month's groups with their tables, matches and late
/// seats; one player's month; the settings, the days kept from automatic
/// approval and a manual run of the jobs; and the month report with the
/// admin log. Every rule is the server's: these pages show what it decided
/// and send the admin's choice, nothing more.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../../h2h/h2h_texts.dart';
import '../../widgets/admin_ui_kit.dart';
import 'h2h_admin_section.dart';

/// `GET /admin/h2h/groups?day=`.
final adminH2hGroupsProvider = FutureProvider.autoDispose
    .family<H2hAdminGroupsDto, String?>((ref, day) async {
      return switch (await ref.watch(adminApiProvider).h2hGroups(day: day)) {
        Ok<H2hAdminGroupsDto>(:final value) => value,
        Err<H2hAdminGroupsDto>(:final error) => throw error,
      };
    });

/// `GET /admin/h2h/groups/{id}/rounds/{n}?day=`.
final adminH2hGroupRoundProvider = FutureProvider.autoDispose
    .family<H2hGroupRoundDto, ({String leagueId, int round, String? day})>((
      ref,
      key,
    ) async {
      return switch (await ref
          .watch(adminApiProvider)
          .h2hGroupRound(
            leagueId: key.leagueId,
            round: key.round,
            day: key.day,
          )) {
        Ok<H2hGroupRoundDto>(:final value) => value,
        Err<H2hGroupRoundDto>(:final error) => throw error,
      };
    });

/// `GET /admin/h2h/players/{id}`.
final adminH2hPlayerProvider = FutureProvider.autoDispose
    .family<MyH2hLeagueDto, String>((ref, userId) async {
      return switch (await ref.watch(adminApiProvider).h2hPlayer(userId)) {
        Ok<MyH2hLeagueDto>(:final value) => value,
        Err<MyH2hLeagueDto>(:final error) => throw error,
      };
    });

/// `GET /admin/h2h/controls?day=`.
final adminH2hControlsProvider = FutureProvider.autoDispose
    .family<H2hControlsDto, String?>((ref, day) async {
      return switch (await ref.watch(adminApiProvider).h2hControls(day: day)) {
        Ok<H2hControlsDto>(:final value) => value,
        Err<H2hControlsDto>(:final error) => throw error,
      };
    });

/// `GET /admin/h2h/report?day=`.
final adminH2hReportProvider = FutureProvider.autoDispose
    .family<H2hMonthReportDto, String?>((ref, day) async {
      return switch (await ref.watch(adminApiProvider).h2hReport(day: day)) {
        Ok<H2hMonthReportDto>(:final value) => value,
        Err<H2hMonthReportDto>(:final error) => throw error,
      };
    });

/// A line of the admin log, in words.
String h2hAdminActionLabel(String action) => switch (action) {
  'settings_saved' => 'حفظ الإعدادات',
  'day_excluded' => 'استبعاد يوم من الاعتماد التلقائي',
  'day_included' => 'إرجاع يوم إلى الاعتماد التلقائي',
  'round_approved' => 'اعتماد جولة',
  'round_withdrawn' => 'سحب جولة',
  'seat_added' => 'إضافة لاعب متأخر',
  'jobs_run' => 'تشغيل مهام الدوري',
  'pilot_started' => 'بدء الشهر التجريبي',
  'groups_added' => 'إضافة مجموعات',
  _ => action,
};

/// What a line of the admin log was done to, in words; empty when the
/// line carries nothing this build knows how to say.
String h2hAdminActionDetail(Map<String, Object?> detail) {
  final List<String> parts = <String>[];
  final Object? day = detail['day'];
  if (day is String) parts.add(h2hDayLabel(day));
  final Object? round = detail['round'];
  if (round is int) parts.add('الجولة $round');
  final Object? slot = detail['slot'];
  if (slot is int) parts.add('المقعد ${slot + 1}');
  final Object? auto = detail['auto_approve'];
  if (auto is bool) {
    parts.add(auto ? 'الاعتماد التلقائي: يعمل' : 'الاعتماد التلقائي: متوقف');
  }
  final Object? lead = detail['lead_hours'];
  if (lead is int) parts.add('المهلة $lead ساعة');
  final Object? days = detail['min_active_days'];
  if (days is int) parts.add('أيام النشاط $days');
  final Object? approved = detail['approved'];
  if (approved is int) parts.add('اعتُمدت $approved');
  final Object? locked = detail['locked'];
  if (locked is int) parts.add('جُمّدت $locked');
  final Object? closed = detail['closed_months'];
  if (closed is int) parts.add('أُغلق $closed');
  final Object? seats = detail['drawn_seats'];
  if (seats is int) parts.add('مقاعد القرعة $seats');
  final Object? groups = detail['groups'];
  if (groups is int) parts.add('المجموعات $groups');
  final Object? added = detail['seats'];
  if (added is int) parts.add('المقاعد $added');
  return parts.join(' · ');
}

/// A month's outcome in words.
String h2hOutcomeLabel(String outcome) => switch (outcome) {
  'promoted' => 'صعود',
  'held' => 'بقاء',
  'relegated' => 'هبوط',
  'out' => 'خارج القرعة القادمة',
  _ => outcome,
};

/// A player's state in the month, in words.
String h2hAdminStateLabel(String state) => switch (state) {
  'not_started' => 'لم يبدأ الدوري لهذا اللاعب',
  'draw_pending' => 'بانتظار قرعة الشهر',
  'not_in_draw' => 'ليس في قرعة هذا الشهر',
  'open' => 'يلعب هذا الشهر',
  _ => state,
};

List<Widget> _loading() => const <Widget>[
  Padding(
    padding: EdgeInsets.all(AppSpacing.xl),
    child: Center(child: CircularProgressIndicator()),
  ),
];

List<Widget> _failed(Object error, VoidCallback onRetry, String what) =>
    <Widget>[
      Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            Text(
              error is AppError ? h2hAdminErrorMessage(error) : what,
              key: const Key('admin.h2h.tab.error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    ];

TextStyle? _heading(BuildContext context) => context.text.titleSmall?.copyWith(
  color: context.tokens.textPrimary,
  fontWeight: FontWeight.w700,
);

TextStyle? _muted(BuildContext context) =>
    context.text.bodySmall?.copyWith(color: context.tokens.textSecondary);

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          key: const Key('admin.h2h.confirm.cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('admin.h2h.confirm.ok'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer ?? false;
}

// ---------------------------------------------------------------------------
// المجموعات

/// Every group of the month: its table, the matches of a round, and a late
/// seat in an empty place.
class H2hAdminGroupsTab extends ConsumerStatefulWidget {
  /// Creates the tab for the month containing [day] (the server's month
  /// when null), under [header].
  const H2hAdminGroupsTab({super.key, required this.day, required this.header});

  /// A day of the month shown, or null for the current one.
  final String? day;

  /// The dashboard's header, drawn first in the list.
  final List<Widget> header;

  @override
  ConsumerState<H2hAdminGroupsTab> createState() => _H2hAdminGroupsTabState();
}

class _H2hAdminGroupsTabState extends ConsumerState<H2hAdminGroupsTab> {
  /// The group whose matches are open, by id.
  String? _open;

  /// The round shown for the open group.
  int? _round;

  void _reload() => ref.invalidate(adminH2hGroupsProvider(widget.day));

  Future<void> _seat(H2hAdminGroupDto group) async {
    final String? message = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _LateSeatDialog(group: group, day: widget.day),
    );
    if (message == null || !mounted) return;
    _snack(context, message);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<H2hAdminGroupsDto> groups = ref.watch(
      adminH2hGroupsProvider(widget.day),
    );
    return ListView(
      key: const Key('admin.h2h.groups.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        ...widget.header,
        ...groups.when<List<Widget>>(
          loading: _loading,
          error: (Object error, _) =>
              _failed(error, _reload, 'تعذّر تحميل المجموعات'),
          data: (H2hAdminGroupsDto data) => _content(context, data),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, H2hAdminGroupsDto data) {
    final int free = <int>[
      for (final H2hAdminGroupDto g in data.groups) g.freeSlots.length,
    ].fold(0, (int a, int b) => a + b);
    return <Widget>[
      AdminCard(
        key: const Key('admin.h2h.groups.summary'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(h2hMonthLabel(data.monthStart), style: _heading(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              data.drawn
                  ? 'المقاعد: ${data.seatedCount} · المجموعات: '
                        '${data.groups.length} · مقاعد شاغرة: $free'
                  : 'لم تُجرَ قرعة هذا الشهر بعد',
              style: _muted(context),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (data.groups.isEmpty)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'لا مجموعات في هذا الشهر',
            key: Key('admin.h2h.groups.empty'),
            textAlign: TextAlign.center,
          ),
        ),
      for (final H2hAdminGroupDto group in data.groups) ...<Widget>[
        _groupCard(context, data, group),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }

  Widget _groupCard(
    BuildContext context,
    H2hAdminGroupsDto data,
    H2hAdminGroupDto group,
  ) {
    final AppTokens tokens = context.tokens;
    final bool open = _open == group.leagueId;
    final int size = group.standings.length;
    return AdminCard(
      key: Key('admin.h2h.group.${group.leagueId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${h2hDivisionName(group.division)} · '
            '${h2hGroupName(group.groupIndex)}',
            style: _heading(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$size لاعباً · ${group.freeSlots.length} مقاعد شاغرة · '
            'يصعد ${group.promotionZone} · يهبط ${group.relegationZone}',
            style: _muted(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (group.standings.isEmpty)
            Text('لا لاعبين في هذه المجموعة', style: _muted(context)),
          for (final H2hStandingDto s in group.standings)
            Padding(
              key: Key('admin.h2h.group.${group.leagueId}.${s.userId}'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 4,
                    height: 36,
                    color: s.rank <= group.promotionZone
                        ? tokens.success
                        : (s.rank > size - group.relegationZone
                              ? tokens.error
                              : tokens.border),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${s.rank}. ${s.displayName.isEmpty ? h2hUnnamed : s.displayName}',
                          style: context.text.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                        Text(
                          '${s.leaguePoints} نقطة · فوز ${s.won} · تعادل '
                          '${s.drawn} · خسارة ${s.lost} · نقاط التوقع '
                          '${s.pointsFor}',
                          style: _muted(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              AdminSecondaryButton(
                key: Key('admin.h2h.group.${group.leagueId}.matches'),
                label: open ? 'إخفاء المواجهات' : 'مواجهات الجولات',
                icon: Icons.sports_kabaddi_rounded,
                onPressed: data.rounds.isEmpty
                    ? null
                    : () => setState(() {
                        _open = open ? null : group.leagueId;
                        _round = data.rounds.last.round;
                      }),
              ),
              if (group.freeSlots.isNotEmpty)
                AdminSecondaryButton(
                  key: Key('admin.h2h.group.${group.leagueId}.seat'),
                  label: 'إضافة لاعب متأخر',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: () => unawaited(_seat(group)),
                ),
            ],
          ),
          if (open) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final H2hRoundDto r in data.rounds)
                  ChoiceChip(
                    key: Key(
                      'admin.h2h.group.${group.leagueId}.round.${r.round}',
                    ),
                    label: Text('ج${r.round}'),
                    selected: _round == r.round,
                    onSelected: (_) => setState(() => _round = r.round),
                  ),
              ],
            ),
            if (_round != null)
              _GroupRound(
                leagueId: group.leagueId,
                round: _round!,
                day: widget.day,
              ),
          ],
        ],
      ),
    );
  }
}

/// Every match of one round of one group: names and stored points.
class _GroupRound extends ConsumerWidget {
  const _GroupRound({
    required this.leagueId,
    required this.round,
    required this.day,
  });

  final String leagueId;
  final int round;
  final String? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<H2hGroupRoundDto> value = ref.watch(
      adminH2hGroupRoundProvider((leagueId: leagueId, round: round, day: day)),
    );
    final List<Widget> children = value.when<List<Widget>>(
      loading: _loading,
      error: (Object error, _) => _failed(
        error,
        () => ref.invalidate(
          adminH2hGroupRoundProvider((
            leagueId: leagueId,
            round: round,
            day: day,
          )),
        ),
        'تعذّر تحميل المواجهات',
      ),
      data: (H2hGroupRoundDto data) => <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            'الجولة ${data.round} · ${h2hDayLabel(data.day)} · '
            '${h2hRoundStatusLabel(data.status)}',
            style: _heading(context),
          ),
        ),
        for (final H2hGroupMatchDto m in data.matches)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              '${m.homeName.isEmpty ? h2hUnnamed : m.homeName} '
              '${m.homePoints ?? '-'} × '
              '${m.awayPoints == null ? '-' : h2hPointsLabel(m.awayPoints!)} '
              '${m.awayUserId == null ? h2hAverageOpponent : ((m.awayName ?? '').isEmpty ? h2hUnnamed : m.awayName!)}'
              '${_winnerNote(m.winner)}',
              style: context.text.bodyMedium?.copyWith(
                color: context.tokens.textPrimary,
              ),
            ),
          ),
      ],
    );
    return Column(
      key: Key('admin.h2h.group.$leagueId.view.$round'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  static String _winnerNote(String? winner) => switch (winner) {
    'home' => ' · يتقدم الأول',
    'away' => ' · يتقدم الثاني',
    'draw' => ' · تعادل',
    'none' => ' · خسر الطرفان',
    _ => '',
  };
}

/// Finds a player by name or email and seats them in an empty place of
/// [group]. Pops with the message to show, or null when cancelled.
class _LateSeatDialog extends ConsumerStatefulWidget {
  const _LateSeatDialog({required this.group, required this.day});

  final H2hAdminGroupDto group;
  final String? day;

  @override
  ConsumerState<_LateSeatDialog> createState() => _LateSeatDialogState();
}

class _LateSeatDialogState extends ConsumerState<_LateSeatDialog> {
  final TextEditingController _search = TextEditingController();
  List<UserSummaryDto> _found = const <UserSummaryDto>[];
  UserSummaryDto? _picked;
  late int _slot = widget.group.freeSlots.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final String query = _search.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<UserListDto> result = await ref
        .read(adminApiProvider)
        .listUsers(search: query, limit: 20);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok<UserListDto>(:final value):
          _found = value.users;
          _picked = null;
          if (value.users.isEmpty) _error = 'لا لاعب بهذا الاسم أو البريد';
        case Err<UserListDto>(:final error):
          _error = h2hAdminErrorMessage(error);
      }
    });
  }

  Future<void> _add() async {
    final UserSummaryDto? picked = _picked;
    if (picked == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .addH2hSeat(
          H2hSeatRequestDto(
            leagueId: widget.group.leagueId,
            userId: picked.id,
            slot: _slot,
            day: widget.day,
          ),
        );
    if (!mounted) return;
    switch (result) {
      case Ok<bool>():
        Navigator.of(context).pop(
          'أُضيف ${picked.displayName.isEmpty ? h2hUnnamed : picked.displayName}'
          ' في المقعد ${_slot + 1}',
        );
      case Err<bool>(:final error):
        setState(() {
          _busy = false;
          _error = h2hAdminErrorMessage(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'لاعب متأخر في ${h2hGroupName(widget.group.groupIndex)} · '
        '${h2hDivisionName(widget.group.division)}',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'يلعب من الجولة التالية لانضمامه، ومقعده يلعب متوسط المجموعة '
                'قبل ذلك.',
                style: _muted(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminTextField(
                key: const Key('admin.h2h.seat.search'),
                controller: _search,
                hint: 'الاسم أو البريد',
                prefixIcon: Icons.search_rounded,
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminSecondaryButton(
                key: const Key('admin.h2h.seat.find'),
                label: 'بحث',
                icon: Icons.search_rounded,
                loading: _busy && _picked == null,
                onPressed: _busy ? null : () => unawaited(_find()),
              ),
              for (final UserSummaryDto u in _found)
                ListTile(
                  key: Key('admin.h2h.seat.user.${u.id}'),
                  selected: _picked?.id == u.id,
                  leading: Icon(
                    _picked?.id == u.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  title: Text(
                    u.displayName.isEmpty ? h2hUnnamed : u.displayName,
                  ),
                  subtitle: u.email == null ? null : Text(u.email!),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => setState(() => _picked = u),
                ),
              if (_picked != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                DropdownButton<int>(
                  key: const Key('admin.h2h.seat.slot'),
                  value: _slot,
                  isExpanded: true,
                  items: <DropdownMenuItem<int>>[
                    for (final int slot in widget.group.freeSlots)
                      DropdownMenuItem<int>(
                        value: slot,
                        child: Text('المقعد ${slot + 1}'),
                      ),
                  ],
                  onChanged: (int? slot) {
                    if (slot != null) setState(() => _slot = slot);
                  },
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  key: const Key('admin.h2h.seat.error'),
                  style: context.text.bodySmall?.copyWith(
                    color: context.tokens.errorText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('admin.h2h.seat.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('admin.h2h.seat.add'),
          onPressed: _busy || _picked == null ? null : () => unawaited(_add()),
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// لاعب

/// One player's month, as they see it, found by name or email.
class H2hAdminPlayerTab extends ConsumerStatefulWidget {
  /// Creates the tab under [header].
  const H2hAdminPlayerTab({super.key, required this.header});

  /// The dashboard's header, drawn first in the list.
  final List<Widget> header;

  @override
  ConsumerState<H2hAdminPlayerTab> createState() => _H2hAdminPlayerTabState();
}

class _H2hAdminPlayerTabState extends ConsumerState<H2hAdminPlayerTab> {
  final TextEditingController _search = TextEditingController();
  List<UserSummaryDto> _found = const <UserSummaryDto>[];
  UserSummaryDto? _picked;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final String query = _search.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final Result<UserListDto> result = await ref
        .read(adminApiProvider)
        .listUsers(search: query, limit: 20);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok<UserListDto>(:final value):
          _found = value.users;
          _picked = null;
          if (value.users.isEmpty) _message = 'لا لاعب بهذا الاسم أو البريد';
        case Err<UserListDto>(:final error):
          _message = h2hAdminErrorMessage(error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final UserSummaryDto? picked = _picked;
    return ListView(
      key: const Key('admin.h2h.player.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        ...widget.header,
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('ابحث عن لاعب', style: _heading(context)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'ترى شهره كما يراه هو: مجموعته وترتيبه وجولاته ونقاطه.',
                style: _muted(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminTextField(
                key: const Key('admin.h2h.player.search'),
                controller: _search,
                hint: 'الاسم أو البريد',
                prefixIcon: Icons.search_rounded,
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminPrimaryButton(
                key: const Key('admin.h2h.player.find'),
                label: 'بحث',
                icon: Icons.search_rounded,
                loading: _busy,
                onPressed: _busy ? null : () => unawaited(_find()),
              ),
              if (_message != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _message!,
                  key: const Key('admin.h2h.player.message'),
                  style: _muted(context),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final UserSummaryDto u in _found)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              key: Key('admin.h2h.player.user.${u.id}'),
              selected: picked?.id == u.id,
              title: Text(u.displayName.isEmpty ? h2hUnnamed : u.displayName),
              subtitle: u.email == null ? null : Text(u.email!),
              onTap: () => setState(() => _picked = u),
            ),
          ),
        if (picked != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _PlayerMonth(user: picked),
        ],
      ],
    );
  }
}

/// The month of [user], as `GET /me/h2h-league` reads it for them.
class _PlayerMonth extends ConsumerWidget {
  const _PlayerMonth({required this.user});

  final UserSummaryDto user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MyH2hLeagueDto> value = ref.watch(
      adminH2hPlayerProvider(user.id),
    );
    final List<Widget> children = value.when<List<Widget>>(
      loading: _loading,
      error: (Object error, _) => _failed(
        error,
        () => ref.invalidate(adminH2hPlayerProvider(user.id)),
        'تعذّر تحميل شهر اللاعب',
      ),
      data: (MyH2hLeagueDto month) => _month(context, month),
    );
    return AdminCard(
      key: Key('admin.h2h.player.month.${user.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  List<Widget> _month(BuildContext context, MyH2hLeagueDto month) {
    final String name = user.displayName.isEmpty
        ? h2hUnnamed
        : user.displayName;
    final bool open = month.state == 'open';
    return <Widget>[
      Text(
        '$name · ${h2hMonthLabel(month.monthStart)}',
        style: _heading(context),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        h2hAdminStateLabel(month.state),
        key: const Key('admin.h2h.player.state'),
        style: _muted(context),
      ),
      if (open) ...<Widget>[
        Text(
          '${h2hDivisionName(month.division ?? 4)} · '
          '${h2hGroupName(month.groupIndex ?? 0)}'
          '${month.isPilot ? ' · شهر تجريبي' : ''}',
          style: _muted(context),
        ),
        Text(
          month.myRank > 0
              ? 'المركز ${h2hRankLabel(month.myRank, month.standings.length)}'
              : 'لا ترتيب قبل أول جولة مكتملة',
          style: _muted(context),
        ),
        Text(h2hDaysLeftLabel(month.daysLeft), style: _muted(context)),
        const SizedBox(height: AppSpacing.sm),
        if (month.rounds.isEmpty)
          Text('لا جولات معتمدة بعد', style: _muted(context)),
        for (final H2hRoundViewDto r in month.rounds)
          Padding(
            key: Key('admin.h2h.player.round.${r.round}'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              'الجولة ${r.round} · ${h2hDayLabel(r.day)} · '
              '${h2hRoundStatusLabel(r.status)} · '
              '${r.opponentUserId == null ? h2hAverageOpponent : ((r.opponentName ?? '').isEmpty ? h2hUnnamed : r.opponentName!)}'
              '${r.myPoints == null ? '' : ' · ${r.myPoints} - ${r.opponentPoints == null ? '-' : h2hPointsLabel(r.opponentPoints!)}'}'
              '${r.result == null ? '' : ' · ${h2hResultLabel(r.result!)}'}',
              style: context.text.bodyMedium?.copyWith(
                color: context.tokens.textPrimary,
              ),
            ),
          ),
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// الإعدادات

/// The settings, the days kept from automatic approval and a manual run of
/// the league's jobs.
class H2hAdminControlsTab extends ConsumerStatefulWidget {
  /// Creates the tab for the month containing [day] (the server's month
  /// when null), under [header].
  const H2hAdminControlsTab({
    super.key,
    required this.day,
    required this.header,
  });

  /// A day of the month shown, or null for the current one.
  final String? day;

  /// The dashboard's header, drawn first in the list.
  final List<Widget> header;

  @override
  ConsumerState<H2hAdminControlsTab> createState() =>
      _H2hAdminControlsTabState();
}

class _H2hAdminControlsTabState extends ConsumerState<H2hAdminControlsTab> {
  /// The admin's edits; null keeps what the server sent.
  bool? _auto;
  int? _lead;
  int? _days;
  bool _busy = false;

  /// Groups to add to the month open now.
  int _extraGroups = 1;

  void _reload() => ref.invalidate(adminH2hControlsProvider(widget.day));

  Future<void> _save(H2hSettingsDto settings) async {
    setState(() => _busy = true);
    final Result<H2hSettingsDto> result = await ref
        .read(adminApiProvider)
        .saveH2hSettings(
          H2hSettingsRequestDto(
            autoApprove: _auto ?? settings.autoApprove,
            leadHours: _lead ?? settings.leadHours,
            minActiveDays: _days ?? settings.minActiveDays,
          ),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Ok<H2hSettingsDto>) {
        _auto = null;
        _lead = null;
        _days = null;
      }
    });
    _snack(context, switch (result) {
      Ok<H2hSettingsDto>() => 'حُفظت الإعدادات',
      Err<H2hSettingsDto>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
  }

  Future<void> _toggleDay(H2hControlDayDto day) async {
    setState(() => _busy = true);
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .setH2hDayExcluded(day: day.day, excluded: !day.excluded);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, switch (result) {
      Ok<bool>() =>
        day.excluded
            ? 'عاد ${h2hDayLabel(day.day)} إلى الاعتماد التلقائي'
            : 'استُبعد ${h2hDayLabel(day.day)} من الاعتماد التلقائي',
      Err<bool>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
  }

  Future<void> _runJobs() async {
    final bool sure = await _confirm(
      context,
      title: 'تشغيل مهام الدوري الآن',
      body:
          'يعتمد الخادم الأيام المستحقة ويجمّد الجولات التي بدأت ويغلق الشهر '
          'المنتهي ويجري قرعة الشهر الجديد إن حان وقتها، كما يفعل كل خمس '
          'دقائق. لا يتكرر شيء مرتين.',
      action: 'تشغيل',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final Result<H2hJobsRunDto> result = await ref
        .read(adminApiProvider)
        .runH2hJobs();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, switch (result) {
      Ok<H2hJobsRunDto>(:final value) =>
        'اعتُمدت ${value.approved} · جُمّدت ${value.locked} · أُغلق '
            '${value.closedMonths} شهر · مقاعد القرعة ${value.drawnSeats}',
      Err<H2hJobsRunDto>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
    ref.invalidate(adminH2hRoundsProvider(widget.day));
  }

  Future<void> _addGroups() async {
    final int count = _extraGroups;
    final bool sure = await _confirm(
      context,
      title: 'إضافة مجموعات إلى الشهر الجاري',
      body:
          'عدد المجموعات: $count، حتى ${count * 20} لاعباً من المنتظرين، '
          'الأكثر مشاركة أولاً. لا يمكن التراجع عن الإضافة.',
      action: 'إضافة',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final Result<H2hGroupsAddedDto> result = await ref
        .read(adminApiProvider)
        .addH2hGroups(groups: count);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, switch (result) {
      Ok<H2hGroupsAddedDto>(:final value) =>
        'أُضيفت المجموعات: ${value.groups.length} · المقاعد: ${value.seats} '
            '· بلا مقعد بعد: ${value.waiting}',
      Err<H2hGroupsAddedDto>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
    ref.invalidate(adminH2hGroupsProvider(widget.day));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<H2hControlsDto> controls = ref.watch(
      adminH2hControlsProvider(widget.day),
    );
    return ListView(
      key: const Key('admin.h2h.controls.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        ...widget.header,
        ...controls.when<List<Widget>>(
          loading: _loading,
          error: (Object error, _) =>
              _failed(error, _reload, 'تعذّر تحميل الإعدادات'),
          data: (H2hControlsDto data) => _content(context, data),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, H2hControlsDto data) {
    final H2hSettingsDto s = data.settings;
    final bool auto = _auto ?? s.autoApprove;
    final int lead = _lead ?? s.leadHours;
    final int days = _days ?? s.minActiveDays;
    final bool changed =
        auto != s.autoApprove || lead != s.leadHours || days != s.minActiveDays;
    return <Widget>[
      AdminCard(
        key: const Key('admin.h2h.settings'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('الإعدادات', style: _heading(context)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'الاعتماد التلقائي للأيام التي فيها 6 مباريات أو أكثر',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.tokens.textPrimary,
                    ),
                  ),
                ),
                Switch(
                  key: const Key('admin.h2h.settings.auto'),
                  value: auto,
                  onChanged: _busy
                      ? null
                      : (bool v) => setState(() => _auto = v),
                ),
              ],
            ),
            _Stepper(
              keyPrefix: 'admin.h2h.settings.lead',
              label: 'يعتمد اليوم قبل أول مباراة بـ $lead ساعة',
              value: lead,
              min: s.leadHoursMin,
              max: s.leadHoursMax,
              enabled: !_busy,
              onChanged: (int v) => setState(() => _lead = v),
            ),
            _Stepper(
              keyPrefix: 'admin.h2h.settings.days',
              label: 'يدخل القرعة من توقّع في $days أيام من الشهر',
              value: days,
              min: s.minActiveDaysMin,
              max: s.minActiveDaysMax,
              enabled: !_busy,
              onChanged: (int v) => setState(() => _days = v),
            ),
            Text(
              'أيام النشاط تُطبَّق عند إغلاق الشهر وعند القرعة التالية.',
              style: _muted(context),
            ),
            if (s.updatedByName != null && s.updatedAt != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'آخر تعديل: ${s.updatedByName!.isEmpty ? 'مشرف' : s.updatedByName!} · '
                '${formatTimestamp(context, s.updatedAt!)}',
                key: const Key('admin.h2h.settings.updated'),
                style: _muted(context),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AdminPrimaryButton(
              key: const Key('admin.h2h.settings.save'),
              label: 'حفظ الإعدادات',
              icon: Icons.save_rounded,
              loading: _busy,
              onPressed: changed && !_busy ? () => unawaited(_save(s)) : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AdminCard(
        key: const Key('admin.h2h.days'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('أيام الشهر', style: _heading(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'اليوم المستبعد لا يعتمده الخادم وحده، ويبقى بإمكانك اعتماده '
              'يدوياً من «الجولات».',
              style: _muted(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (data.days.isEmpty)
              Text(
                'لا أيام قادمة فيها مباريات في هذا الشهر',
                key: const Key('admin.h2h.days.empty'),
                style: _muted(context),
              ),
            for (final H2hControlDayDto d in data.days)
              Padding(
                key: Key('admin.h2h.day.${d.day}'),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${h2hDayLabel(d.day)} · ${d.fixtureCount} مباريات'
                        '${d.round != null ? ' · الجولة ${d.round}' : ''}'
                        '${d.excluded ? ' · مستبعد' : ''}',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (d.round == null)
                      Switch(
                        key: Key('admin.h2h.day.${d.day}.auto'),
                        value: !d.excluded,
                        onChanged: _busy
                            ? null
                            : (_) => unawaited(_toggleDay(d)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AdminCard(
        key: const Key('admin.h2h.jobs'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('مهام الدوري', style: _heading(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'تعمل وحدها كل خمس دقائق. شغّلها الآن بعد تعديل الإعدادات أو '
              'الأيام لترى أثرها فوراً.',
              style: _muted(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            AdminSecondaryButton(
              key: const Key('admin.h2h.jobs.run'),
              label: 'تشغيل المهام الآن',
              icon: Icons.play_arrow_rounded,
              onPressed: _busy ? null : () => unawaited(_runJobs()),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AdminCard(
        key: const Key('admin.h2h.extraGroups'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('مجموعات إضافية', style: _heading(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'تُضاف إلى الشهر الجاري من اللاعبين الذين ليس لهم مقعد وتوقّعوا '
              'في ${s.minActiveDays} أيام منه على الأقل، الأكثر أياماً أولاً، '
              '20 لاعباً في كل مجموعة، في الدرجات التالية للمجموعات الموجودة. '
              'تلعب المجموعة الجديدة كل جولات الشهر بتوقعات أعضائها.',
              style: _muted(context),
            ),
            _Stepper(
              keyPrefix: 'admin.h2h.extraGroups.count',
              label: 'عدد المجموعات: $_extraGroups',
              value: _extraGroups,
              min: 1,
              max: 10,
              enabled: !_busy,
              onChanged: (int v) => setState(() => _extraGroups = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            AdminPrimaryButton(
              key: const Key('admin.h2h.extraGroups.add'),
              label: 'إضافة المجموعات',
              icon: Icons.group_add_rounded,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_addGroups()),
            ),
          ],
        ),
      ),
    ];
  }
}

/// A whole number between [min] and [max] with − and + buttons.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            key: Key('$keyPrefix.label'),
            style: context.text.bodyMedium?.copyWith(
              color: context.tokens.textPrimary,
            ),
          ),
        ),
        IconButton(
          key: Key('$keyPrefix.dec'),
          tooltip: 'إنقاص',
          icon: const Icon(Icons.remove_rounded),
          onPressed: enabled && value > min ? () => onChanged(value - 1) : null,
        ),
        IconButton(
          key: Key('$keyPrefix.inc'),
          tooltip: 'زيادة',
          icon: const Icon(Icons.add_rounded),
          onPressed: enabled && value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// التقرير والسجل

/// How the month went, and the latest lines of the admin log.
class H2hAdminReportTab extends ConsumerWidget {
  /// Creates the tab for the month containing [day] (the server's month
  /// when null), under [header].
  const H2hAdminReportTab({super.key, required this.day, required this.header});

  /// A day of the month shown, or null for the current one.
  final String? day;

  /// The dashboard's header, drawn first in the list.
  final List<Widget> header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<H2hMonthReportDto> report = ref.watch(
      adminH2hReportProvider(day),
    );
    final AsyncValue<H2hControlsDto> controls = ref.watch(
      adminH2hControlsProvider(day),
    );
    return ListView(
      key: const Key('admin.h2h.report.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        ...header,
        ...report.when<List<Widget>>(
          loading: _loading,
          error: (Object error, _) => _failed(
            error,
            () => ref.invalidate(adminH2hReportProvider(day)),
            'تعذّر تحميل التقرير',
          ),
          data: (H2hMonthReportDto r) => <Widget>[_reportCard(context, r)],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('سجل الإجراءات', style: _heading(context)),
        const SizedBox(height: AppSpacing.sm),
        ...controls.when<List<Widget>>(
          loading: _loading,
          error: (Object error, _) => _failed(
            error,
            () => ref.invalidate(adminH2hControlsProvider(day)),
            'تعذّر تحميل السجل',
          ),
          data: (H2hControlsDto data) => <Widget>[
            if (data.actions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'لا إجراءات مسجّلة بعد',
                  key: Key('admin.h2h.log.empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            for (final H2hAdminActionDto a in data.actions)
              AdminCard(
                key: Key('admin.h2h.log.${a.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      h2hAdminActionLabel(a.action),
                      style: context.text.bodyMedium?.copyWith(
                        color: context.tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (h2hAdminActionDetail(a.detail).isNotEmpty)
                      Text(
                        h2hAdminActionDetail(a.detail),
                        style: _muted(context),
                      ),
                    Text(
                      '${a.actorId == null ? 'النظام' : ((a.actorName ?? '').isEmpty ? 'مشرف' : a.actorName!)} · '
                      '${formatTimestamp(context, a.actedAt)}',
                      style: _muted(context),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _reportCard(BuildContext context, H2hMonthReportDto r) {
    final List<String> divisions = <String>[
      for (final MapEntry<String, int> e in r.groupsByDivision.entries)
        '${h2hDivisionName(int.tryParse(e.key) ?? 4)}: ${e.value}',
    ];
    final List<String> outcomes = <String>[
      for (final MapEntry<String, int> e in r.outcomes.entries)
        '${h2hOutcomeLabel(e.key)}: ${e.value}',
    ];
    return AdminCard(
      key: const Key('admin.h2h.report'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'تقرير ${h2hMonthLabel(r.monthStart)}'
            '${r.isPilot ? ' (تجريبي)' : ''}',
            style: _heading(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            r.drawn
                ? 'القرعة: ${r.drawnAt == null ? 'أُجريت' : formatTimestamp(context, r.drawnAt!)}'
                : 'القرعة: لم تُجرَ بعد',
            key: const Key('admin.h2h.report.draw'),
            style: _muted(context),
          ),
          if (r.drawn) ...<Widget>[
            Text(
              'مقاعد القرعة: ${r.drawnSeats} · المقاعد الآن: ${r.seats}',
              key: const Key('admin.h2h.report.seats'),
              style: _muted(context),
            ),
            if (divisions.isNotEmpty)
              Text(
                'المجموعات: ${divisions.join(' · ')}',
                style: _muted(context),
              ),
          ],
          Text(
            r.closed
                ? 'الإغلاق: ${r.closedAt == null ? 'تم' : formatTimestamp(context, r.closedAt!)}'
                      ' · حُكم على ${r.closedMembers} لاعباً'
                : 'الإغلاق: لم يُغلق الشهر بعد',
            key: const Key('admin.h2h.report.closed'),
            style: _muted(context),
          ),
          if (outcomes.isNotEmpty)
            Text(outcomes.join(' · '), style: _muted(context)),
        ],
      ),
    );
  }
}
