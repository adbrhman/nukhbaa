/// قسم «المباريات»: كل ما يخصّ المباراة في مكان واحد.
///
/// الإضافة والتعديل والحذف والإخفاء أزرار هنا، لا أقسام مستقلة في القائمة:
/// قائمة مباريات الشهر، ومرشّح «الكل | ظاهرة | مخفية | تجريبية»، وإخفاء
/// مباراة أو إظهارها من سطرها فورًا، وتحديد عدة مباريات (أو كل ما يعرضه
/// المرشّح) لإخفائها أو إظهارها دفعة واحدة بعد تأكيد.
///
/// الحماية في الخادم لا هنا (الترحيل 0098): المخفية لا تصل إلى لاعب ولا
/// تقبل توقّعًا ولا تُحتسب، والتجريبية لا يراها ولا يتوقّعها إلا مشرف ولا
/// تُحتسب لها نقاط أبدًا.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/ui/app_badge.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/competition_providers.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';
import 'fixture_edit_section.dart';
import 'fixture_schedule_section.dart';

/// The four views of a month's fixtures.
enum AdminFixtureFilter {
  /// Every fixture of the month.
  all,

  /// What the players see: neither hidden nor a test.
  visible,

  /// Hidden by an admin.
  hidden,

  /// Test fixtures.
  test,
}

/// The chip label of [filter].
String adminFixtureFilterLabel(AdminFixtureFilter filter) => switch (filter) {
  AdminFixtureFilter.all => 'الكل',
  AdminFixtureFilter.visible => 'ظاهرة',
  AdminFixtureFilter.hidden => adminFixtureHiddenLabel,
  AdminFixtureFilter.test => adminFixtureTestLabel,
};

/// Whether [fixture] belongs in [filter]'s view.
bool adminFixtureFilterMatches(
  AdminFixtureFilter filter,
  SeasonFixtureCardDto fixture,
) => switch (filter) {
  AdminFixtureFilter.all => true,
  AdminFixtureFilter.visible => !fixture.hidden && !fixture.isTest,
  AdminFixtureFilter.hidden => fixture.hidden,
  AdminFixtureFilter.test => fixture.isTest,
};

/// قسم «المباريات» في لوحة الأدمن.
class FixturesAdminSection extends ConsumerStatefulWidget {
  /// ينشئ القسم.
  const FixturesAdminSection({super.key});

  @override
  ConsumerState<FixturesAdminSection> createState() =>
      _FixturesAdminSectionState();
}

class _FixturesAdminSectionState extends ConsumerState<FixturesAdminSection> {
  /// The month the admin picked; until then, the current one.
  String? _pickedSeasonId;
  AdminFixtureFilter _filter = AdminFixtureFilter.all;
  final Set<String> _selected = <String>{};

  /// The month covering now, else the newest: the list opens on the month
  /// the admin is working in without a tap.
  static String? _defaultMonth(List<SeasonDto> months) {
    if (months.isEmpty) return null;
    final DateTime now = DateTime.now().toUtc();
    for (final SeasonDto month in months) {
      if (!now.isBefore(month.startAt) && now.isBefore(month.endAt)) {
        return month.id;
      }
    }
    return months.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final List<SeasonDto> months =
        ref.watch(monthlySeasonsProvider).value ?? const <SeasonDto>[];
    final String? seasonId = _pickedSeasonId ?? _defaultMonth(months);
    final AsyncValue<FixtureVisibilityResultDto>? visibility = ref.watch(
      fixtureVisibilityControllerProvider,
    );
    final AsyncValue<bool>? removal = ref.watch(
      removeFixtureControllerProvider,
    );
    final bool busy =
        visibility is AsyncLoading<FixtureVisibilityResultDto> ||
        removal is AsyncLoading<bool>;

    return ListView(
      key: const Key('admin.matches.list'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'المباريات',
          subtitle: 'أضف مباريات الشهر وعدّلها وأخفِها أو احذفها من مكان واحد',
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MonthPickerField(
                enabled: !busy,
                selectedId: seasonId,
                onSelected: (SeasonDto month) => setState(() {
                  _pickedSeasonId = month.id;
                  _selected.clear();
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.matches.add'),
                label: 'إضافة مباراة',
                icon: Icons.add_circle_outline_rounded,
                onPressed: busy ? null : () => _openAdd(seasonId),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (visibility is AsyncError<FixtureVisibilityResultDto>) ...<Widget>[
          AdminErrorBanner(
            key: const Key('admin.matches.error'),
            message: ErrorPresenter.message(visibility.error as AppError),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (visibility is AsyncData<FixtureVisibilityResultDto>) ...<Widget>[
          AdminSuccessBanner(
            key: const Key('admin.matches.result'),
            message: _visibilityMessage(visibility.value),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (removal is AsyncError<bool>) ...<Widget>[
          AdminErrorBanner(
            key: const Key('admin.matches.deleteError'),
            message: ErrorPresenter.message(removal.error as AppError),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (seasonId != null) _fixtures(context, seasonId, busy),
      ],
    );
  }

  Widget _fixtures(BuildContext context, String seasonId, bool busy) {
    final AsyncValue<List<SeasonFixtureCardDto>> fixtures = ref.watch(
      adminSeasonFixturesProvider(seasonId),
    );
    return fixtures.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => AdminErrorBanner(
        key: const Key('admin.matches.loadError'),
        message: ErrorPresenter.message(error as AppError),
      ),
      data: (List<SeasonFixtureCardDto> all) {
        final List<SeasonFixtureCardDto> shown = <SeasonFixtureCardDto>[
          for (final SeasonFixtureCardDto f in all)
            if (adminFixtureFilterMatches(_filter, f)) f,
        ]..sort((a, b) => _kickoffOf(b).compareTo(_kickoffOf(a)));
        final List<String> shownIds = <String>[
          for (final SeasonFixtureCardDto f in shown) f.fixtureId,
        ];
        final int selectedCount = shownIds.where(_selected.contains).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final AdminFixtureFilter filter
                    in AdminFixtureFilter.values)
                  ChoiceChip(
                    key: Key('admin.matches.filter.${filter.name}'),
                    label: Text(
                      '${adminFixtureFilterLabel(filter)} '
                      '(${all.where((f) => adminFixtureFilterMatches(filter, f)).length})',
                    ),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() {
                      _filter = filter;
                      _selected.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (shown.isEmpty)
              const AdminEmptyState(
                icon: Icons.sports_soccer_outlined,
                title: 'لا مباريات في هذا العرض',
              )
            else ...<Widget>[
              _SelectionBar(
                total: shown.length,
                selected: selectedCount,
                enabled: !busy,
                onSelectAll: (bool all) => setState(() {
                  if (all) {
                    _selected.addAll(shownIds);
                  } else {
                    _selected.removeAll(shownIds);
                  }
                }),
                onHide: () => _confirmBulk(seasonId, [
                  for (final f in shown)
                    if (_selected.contains(f.fixtureId)) f,
                ], hidden: true),
                onShow: () => _confirmBulk(seasonId, [
                  for (final f in shown)
                    if (_selected.contains(f.fixtureId)) f,
                ], hidden: false),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final SeasonFixtureCardDto fixture in shown) ...<Widget>[
                _FixtureRow(
                  fixture: fixture,
                  selected: _selected.contains(fixture.fixtureId),
                  enabled: !busy,
                  onSelected: (bool value) => setState(() {
                    if (value) {
                      _selected.add(fixture.fixtureId);
                    } else {
                      _selected.remove(fixture.fixtureId);
                    }
                  }),
                  onEdit: () => _openEdit(seasonId, fixture),
                  onToggleHidden: () => _setHidden(seasonId, [
                    fixture.fixtureId,
                  ], hidden: !fixture.hidden),
                  onDelete: () => _confirmDelete(seasonId, fixture),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ],
        );
      },
    );
  }

  static DateTime _kickoffOf(SeasonFixtureCardDto fixture) =>
      DateTime.tryParse(fixture.kickoffAt ?? '') ?? DateTime.utc(1970);

  static String _visibilityMessage(FixtureVisibilityResultDto result) {
    final int n = result.changed.length;
    if (n == 0) return 'لم يتغيّر شيء: المباريات المحددة على حالها أصلًا';
    return result.hidden
        ? 'أُخفيت $n من المباريات عن اللاعبين'
        : 'أُظهرت $n من المباريات للاعبين';
  }

  Future<void> _setHidden(
    String seasonId,
    List<String> fixtureIds, {
    required bool hidden,
  }) async {
    await ref
        .read(fixtureVisibilityControllerProvider.notifier)
        .setHidden(seasonId: seasonId, fixtureIds: fixtureIds, hidden: hidden);
    if (!mounted) return;
    if (ref.read(fixtureVisibilityControllerProvider)
        is AsyncData<FixtureVisibilityResultDto>) {
      setState(() => _selected.removeAll(fixtureIds));
    }
  }

  Future<void> _confirmBulk(
    String seasonId,
    List<SeasonFixtureCardDto> fixtures, {
    required bool hidden,
  }) async {
    if (fixtures.isEmpty) return;
    final String verb = hidden ? 'إخفاء' : 'إظهار';
    final List<String> names = <String>[
      for (final SeasonFixtureCardDto f in fixtures.take(5)) _title(f),
    ];
    final int rest = fixtures.length - names.length;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('admin.matches.bulkConfirm'),
        title: Text('$verb ${fixtures.length} من المباريات؟'),
        content: Text(
          <String>[
            ...names,
            if (rest > 0) 'و$rest أخرى',
            '',
            hidden
                ? 'تختفي عن اللاعبين فورًا ولا تقبل توقّعات، ولا يُحذف شيء '
                      'من بياناتها.'
                : 'تعود إلى اللاعبين فورًا كما كانت.',
          ].join('\n'),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.matches.bulkConfirm.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            key: const Key('admin.matches.bulkConfirm.ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(verb),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _setHidden(seasonId, [
      for (final SeasonFixtureCardDto f in fixtures) f.fixtureId,
    ], hidden: hidden);
  }

  Future<void> _confirmDelete(
    String seasonId,
    SeasonFixtureCardDto fixture,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('admin.matches.deleteConfirm'),
        title: Text(l10n.adminRemoveFixtureFromSeasonButton),
        content: Text(
          l10n.adminRemoveFixtureFromSeasonConfirm(
            fixture.homeTeam ?? '',
            fixture.awayTeam ?? '',
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.matches.deleteConfirm.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminRemoveFixtureCancelButton),
          ),
          TextButton(
            key: const Key('admin.matches.deleteConfirm.ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminRemoveFixtureFromSeasonButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(removeFixtureControllerProvider.notifier)
        .remove(seasonId: seasonId, fixtureId: fixture.fixtureId);
    if (!mounted) return;
    setState(() => _selected.remove(fixture.fixtureId));
  }

  Future<void> _openAdd(String? seasonId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _AdminSubPage(
        title: 'إضافة مباراة',
        child: FixtureScheduleSection(initialSeasonId: seasonId),
      ),
    ),
  );

  Future<void> _openEdit(String seasonId, SeasonFixtureCardDto fixture) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _AdminSubPage(
            title: 'تعديل مباراة',
            child: FixtureEditSection(
              initialSeasonId: seasonId,
              initialFixture: fixture,
            ),
          ),
        ),
      );
}

/// "home × away", or the incomplete-data word when a side is missing.
String _title(SeasonFixtureCardDto fixture) {
  final String? home = fixture.homeTeam;
  final String? away = fixture.awayTeam;
  if (home == null || away == null) return fixture.fixtureId;
  return '$home × $away';
}

/// A full page around an admin form opened from the matches list.
class _AdminSubPage extends StatelessWidget {
  const _AdminSubPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tokens.background,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: child),
    );
  }
}

/// "Select all" over what the filter shows, and the bulk buttons.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.total,
    required this.selected,
    required this.enabled,
    required this.onSelectAll,
    required this.onHide,
    required this.onShow,
  });

  final int total;
  final int selected;
  final bool enabled;
  final ValueChanged<bool> onSelectAll;
  final VoidCallback onHide;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final bool? all = selected == 0 ? false : (selected == total ? true : null);
    return AdminCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(
                key: const Key('admin.matches.selectAll'),
                tristate: true,
                value: all,
                onChanged: enabled
                    ? (bool? _) => onSelectAll(selected < total)
                    : null,
              ),
              Expanded(
                child: Text(
                  selected == 0
                      ? 'تحديد الكل ($total)'
                      : 'المحدد: $selected من $total',
                ),
              ),
            ],
          ),
          if (selected > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: AdminSecondaryButton(
                      key: const Key('admin.matches.bulkHide'),
                      label: 'إخفاء ($selected)',
                      icon: Icons.visibility_off_outlined,
                      onPressed: enabled ? onHide : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AdminSecondaryButton(
                      key: const Key('admin.matches.bulkShow'),
                      label: 'إظهار ($selected)',
                      icon: Icons.visibility_outlined,
                      onPressed: enabled ? onShow : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One fixture of the list: its teams, kickoff and flags, a selection box
/// and its three actions.
class _FixtureRow extends StatelessWidget {
  const _FixtureRow({
    required this.fixture,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.onEdit,
    required this.onToggleHidden,
    required this.onDelete,
  });

  final SeasonFixtureCardDto fixture;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onSelected;
  final VoidCallback onEdit;
  final VoidCallback onToggleHidden;
  final VoidCallback onDelete;

  String _kickoffLine(BuildContext context) {
    final DateTime? kickoff = DateTime.tryParse(
      fixture.kickoffAt ?? '',
    )?.toLocal();
    final String? league = fixture.leagueName;
    if (kickoff == null) return league ?? '';
    final String locale = Localizations.localeOf(context).toString();
    final String when =
        '${intl.DateFormat('EEEE d MMMM', locale).format(kickoff)} - '
        '${intl.DateFormat.jm(locale).format(kickoff)}';
    return league == null ? when : '$when · $league';
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String id = fixture.fixtureId;
    return AdminCard(
      key: Key('admin.matches.row.$id'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(
                key: Key('admin.matches.select.$id'),
                value: selected,
                onChanged: enabled
                    ? (bool? value) => onSelected(value ?? false)
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _title(fixture),
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fixture.hidden ? t.textMuted : t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _kickoffLine(context),
                      style: context.text.bodySmall?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (fixture.hidden || fixture.isTest)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.xl,
                top: AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  if (fixture.hidden)
                    const AppBadge(
                      key: Key('admin.matches.hiddenBadge'),
                      label: adminFixtureHiddenLabel,
                      tone: AppBadgeTone.danger,
                      icon: Icons.visibility_off_outlined,
                    ),
                  if (fixture.isTest)
                    const AppBadge(
                      key: Key('admin.matches.testBadge'),
                      label: adminFixtureTestLabel,
                      tone: AppBadgeTone.gold,
                      icon: Icons.science_outlined,
                    ),
                ],
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            children: <Widget>[
              TextButton.icon(
                key: Key('admin.matches.edit.$id'),
                onPressed: enabled ? onEdit : null,
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('تعديل'),
              ),
              TextButton.icon(
                key: Key('admin.matches.toggle.$id'),
                onPressed: enabled ? onToggleHidden : null,
                icon: Icon(
                  fixture.hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                label: Text(fixture.hidden ? 'إظهار' : 'إخفاء'),
              ),
              TextButton.icon(
                key: Key('admin.matches.delete.$id'),
                onPressed: enabled ? onDelete : null,
                icon: Icon(Icons.delete_outline_rounded, color: t.error),
                label: Text('حذف', style: TextStyle(color: t.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
