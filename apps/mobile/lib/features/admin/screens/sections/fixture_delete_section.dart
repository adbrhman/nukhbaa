/// حذف مباراة من شهرها — شاشة مستقلة: الشهر ← المباراة ← تأكيد صريح.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/error/error_presenter.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// شاشة حذف مباراة من شهرها.
///
/// الحذف يبقى محميًا بحوار تأكيد يذكر اسمي الفريقين لا معرّف المباراة،
/// لأن المعرّف لا يميّز شيئًا في ذهن المشرف. والخادم يرفض الحذف أصلًا إن
/// كان أحد قد توقّع المباراة أو سُجّلت لها نتيجة.
class FixtureDeleteSection extends ConsumerStatefulWidget {
  /// ينشئ القسم.
  const FixtureDeleteSection({super.key});

  @override
  ConsumerState<FixtureDeleteSection> createState() =>
      _FixtureDeleteSectionState();
}

class _FixtureDeleteSectionState extends ConsumerState<FixtureDeleteSection> {
  String? _seasonId;
  String? _fixtureId;
  String _homeTeam = '';
  String _awayTeam = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<bool>? state = ref.watch(removeFixtureControllerProvider);
    final bool inFlight = state is AsyncLoading<bool>;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AdminSectionHeader(
          title: l10n.adminFixtureDeleteTab,
          subtitle: l10n.adminRemoveFixtureFromSeasonButton,
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MonthPickerField(
                key: const Key('admin.fixtureDelete.monthField'),
                enabled: !inFlight,
                selectedId: _seasonId,
                onSelected: (SeasonDto month) => setState(() {
                  _seasonId = month.id;
                  _fixtureId = null;
                  _homeTeam = '';
                  _awayTeam = '';
                }),
              ),
              if (_seasonId != null) ...[
                const SizedBox(height: AppSpacing.md),
                SeasonFixturePickerField(
                  keyPrefix: 'admin.fixtureDelete',
                  seasonId: _seasonId!,
                  enabled: !inFlight,
                  selectedId: _fixtureId,
                  onSelected: (SeasonFixtureCardDto fixture) => setState(() {
                    _fixtureId = fixture.fixtureId;
                    _homeTeam = fixture.homeTeam ?? '';
                    _awayTeam = fixture.awayTeam ?? '';
                  }),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (state is AsyncError<bool>)
                AdminErrorBanner(
                  key: const Key('admin.fixtureDelete.error'),
                  message: ErrorPresenter.message(state.error as AppError),
                ),
              if (state is AsyncData<bool>)
                AdminSuccessBanner(
                  key: const Key('admin.fixtureDelete.result'),
                  message: l10n.adminRemoveFixtureFromSeasonSuccess,
                ),
              const SizedBox(height: AppSpacing.md),
              AdminSecondaryButton(
                key: const Key('admin.fixtureDelete.submit'),
                label: l10n.adminRemoveFixtureFromSeasonButton,
                icon: Icons.delete_outline_rounded,
                loading: inFlight,
                onPressed: (inFlight || _fixtureId == null)
                    ? null
                    : _confirmAndRemove,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// يطلب تأكيدًا صريحًا ثم يحذف.
  Future<void> _confirmAndRemove() async {
    final l10n = AppLocalizations.of(context);
    final String seasonId = _seasonId!;
    final String fixtureId = _fixtureId!;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('admin.fixtureDelete.confirm'),
        title: Text(l10n.adminRemoveFixtureFromSeasonButton),
        content: Text(
          l10n.adminRemoveFixtureFromSeasonConfirm(_homeTeam, _awayTeam),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.fixtureDelete.confirm.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminRemoveFixtureCancelButton),
          ),
          TextButton(
            key: const Key('admin.fixtureDelete.confirm.ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminRemoveFixtureFromSeasonButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(removeFixtureControllerProvider.notifier)
        .remove(seasonId: seasonId, fixtureId: fixtureId);
    if (!mounted) return;

    // بعد حذف ناجح لم يعد للمباراة المختارة وجود، فيُفرَّغ الاختيار كي لا
    // يبقى نموذج يشير إلى شيء محذوف.
    if (ref.read(removeFixtureControllerProvider) is AsyncData<bool>) {
      setState(() {
        _fixtureId = null;
        _homeTeam = '';
        _awayTeam = '';
      });
    }
  }
}
