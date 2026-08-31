library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/competition_providers.dart';
import '../../../competition/team_logo_assets.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// قسم "المسابقات الشهرية" في لوحة الأدمن (خطة قسم 9).
///
/// الدفعة الأولى: عرض قراءة فقط — قائمة المسابقات العامة
/// (`competitionListProvider`) وحالة الموسم الحالي لكل واحدة
/// (`currentSeasonProvider`، `GET /competitions/{id}/seasons/current`).
/// الدفعة الثانية (هذه): نموذج إنشاء مسابقة (`CreateCompetitionController`).
/// Start Season لكل مسابقة لا يزال غير مربوط — يُضاف في دفعة لاحقة منفصلة.
class AdminMonthlyCompetitionsSection extends ConsumerWidget {
  const AdminMonthlyCompetitionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<CompetitionDto>> state = ref.watch(
      competitionListProvider,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(title: l10n.adminMonthlyCompetitionsTab),
        switch (state) {
          AsyncData<List<CompetitionDto>>(:final value) when value.isEmpty =>
            AdminEmptyState(
              icon: Icons.calendar_month_rounded,
              title: l10n.adminMonthlyCompetitionsEmpty,
            ),
          AsyncData<List<CompetitionDto>>(:final value) => AdminCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < value.length; i++) ...[
                  _CompetitionCurrentSeasonRow(competition: value[i]),
                  if (i != value.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          AsyncError(:final error) => AdminErrorBanner(
            message: ErrorPresenter.message(error as AppError),
          ),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
        const SizedBox(height: AppSpacing.lg),
        const _CreateCompetitionForm(),
        const SizedBox(height: AppSpacing.lg),
        const _MonthlyCompetitionLogoCatalog(),
      ],
    );
  }
}

/// نموذج إنشاء مسابقة جديدة (`CreateCompetition`، `POST /competitions`).
///
/// `format` ثابت على `football_scoreline` — القيمة الوحيدة الموجودة في
/// [FormatType] حاليًا (لا اختيار في الواجهة له إلى أن يُضاف تنسيق آخر).
class _CreateCompetitionForm extends ConsumerStatefulWidget {
  const _CreateCompetitionForm();

  @override
  ConsumerState<_CreateCompetitionForm> createState() =>
      _CreateCompetitionFormState();
}

class _CreateCompetitionFormState
    extends ConsumerState<_CreateCompetitionForm> {
  final TextEditingController _nameController = TextEditingController();
  String _visibility = 'public';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _nameController.text.trim();
    if (name.isEmpty) return;
    ref
        .read(createCompetitionControllerProvider.notifier)
        .create(
          name: name,
          format: 'football_scoreline',
          visibility: _visibility,
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<CompetitionDto>? state = ref.watch(
      createCompetitionControllerProvider,
    );
    final bool inFlight = state is AsyncLoading<CompetitionDto>;

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(title: l10n.adminCreateCompetitionSectionTitle),
          AdminTextField(
            key: const Key('admin.monthlyCompetitions.nameField'),
            controller: _nameController,
            hint: l10n.adminCompetitionNameLabel,
            enabled: !inFlight,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('admin.monthlyCompetitions.visibilityField'),
            initialValue: _visibility,
            decoration: InputDecoration(labelText: l10n.adminVisibilityLabel),
            items: [
              DropdownMenuItem(
                value: 'public',
                child: Text(l10n.adminVisibilityPublicLabel),
              ),
              DropdownMenuItem(
                value: 'private',
                child: Text(l10n.adminVisibilityPrivateLabel),
              ),
            ],
            onChanged: inFlight
                ? null
                : (String? value) {
                    if (value != null) setState(() => _visibility = value);
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          if (state is AsyncError<CompetitionDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AdminErrorBanner(
                message: ErrorPresenter.message(state.error as AppError),
              ),
            ),
          if (state is AsyncData<CompetitionDto>)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                l10n.adminCreateCompetitionSuccess(state.value.name),
                key: const Key('admin.monthlyCompetitions.createSuccess'),
              ),
            ),
          AdminPrimaryButton(
            key: const Key('admin.monthlyCompetitions.createButton'),
            label: l10n.adminCreateCompetitionButton,
            loading: inFlight,
            onPressed: inFlight ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// صف مسابقة واحدة + حالة موسمها الحالي (شهر تقويمي) + زر بدء موسم جديد.
///
/// `StartSeasonController` (Section 9 -- Monthly Competitions) هو family
/// حسب `competitionId`: كل صف يملك حالة loading/success/error مستقلة تمامًا
/// عن بقية الصفوف. الزر يظهر فقط عندما تأكَّد فعليًا (`AsyncData` بقيمة
/// null) أنه لا يوجد موسم نشط -- لا يظهر أثناء التحميل أو عند الخطأ، تجنبًا
/// لمحاولة بدء موسم متداخل يرفضها الـbackend (قيد `seasons_no_overlap`).
class _CompetitionCurrentSeasonRow extends ConsumerWidget {
  const _CompetitionCurrentSeasonRow({required this.competition});

  final CompetitionDto competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final AsyncValue<SeasonDto?> seasonState = ref.watch(
      currentSeasonProvider(competition.id),
    );
    final AsyncValue<SeasonDto>? startState = ref.watch(
      startSeasonControllerProvider(competition.id),
    );
    final bool starting = startState is AsyncLoading<SeasonDto>;
    final bool noActiveSeasonConfirmed =
        seasonState is AsyncData<SeasonDto?> && seasonState.value == null;

    final Widget statusWidget = switch (seasonState) {
      AsyncData<SeasonDto?>(value: final SeasonDto season?) => Text(
        season.label,
        style: context.text.labelMedium?.copyWith(
          color: t.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      AsyncData<SeasonDto?>() => Text(
        l10n.adminMonthlyCompetitionsNoActiveSeason,
        style: context.text.labelSmall?.copyWith(color: t.textMuted),
      ),
      AsyncError() => Icon(
        Icons.error_outline_rounded,
        color: t.error,
        size: 18,
      ),
      _ => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };

    final Widget trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        statusWidget,
        if (noActiveSeasonConfirmed) ...[
          const SizedBox(width: AppSpacing.sm),
          AdminSecondaryButton(
            key: Key(
              'admin.monthlyCompetitions.startSeasonButton.${competition.id}',
            ),
            label: l10n.adminStartSeasonButton,
            loading: starting,
            onPressed: starting
                ? null
                : () {
                    final DateTime now = DateTime.now().toUtc();
                    ref
                        .read(
                          startSeasonControllerProvider(
                            competition.id,
                          ).notifier,
                        )
                        .start(year: now.year, month: now.month);
                  },
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminListRow(
          leadingIcon: Icons.emoji_events_outlined,
          leadingColor: t.primary,
          title: competition.name,
          trailing: trailing,
        ),
        if (startState is AsyncError<SeasonDto>)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: AdminErrorBanner(
              message: ErrorPresenter.message(startState.error as AppError),
            ),
          ),
      ],
    );
  }
}

class _MonthlyCompetitionLogoCatalog extends StatelessWidget {
  const _MonthlyCompetitionLogoCatalog();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(title: 'شعارات فرق المسابقات الشهرية'),
          Text(
            'الشعارات المحلية المرفقة للمواسم الحالية والقادمة.',
            style: context.text.bodySmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final MonthlyCompetitionLogoGroup group
              in kMonthlyCompetitionLogoGroups) ...[
            Text(
              group.name + '  •  ' + group.season,
              style: context.text.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final String slug in group.slugs)
                  _MonthlyTeamLogoTile(slug: slug),
              ],
            ),
            if (group != kMonthlyCompetitionLogoGroups.last)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _MonthlyTeamLogoTile extends StatelessWidget {
  const _MonthlyTeamLogoTile({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.tokens.border),
            ),
            child: Image.asset(
              'assets/team_logos/' + slug + '.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.shield_outlined, color: context.tokens.textMuted),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            teamLogoLabel(slug),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.text.labelSmall,
          ),
        ],
      ),
    );
  }
}
