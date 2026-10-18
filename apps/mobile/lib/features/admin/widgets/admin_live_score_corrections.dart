library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/providers.dart';
import '../../fixture_prediction/current_month_fixtures_providers.dart';
import '../admin_providers.dart';
import 'admin_ui_kit.dart';

/// The month's real matches the provider reports a running score for that
/// have no result yet: the ones whose score an admin can still correct.
List<CurrentMonthFixtureItemDto> liveScoresToCorrect(
  List<CurrentMonthFixtureItemDto> items,
) {
  return <CurrentMonthFixtureItemDto>[
    for (final CurrentMonthFixtureItemDto item in items)
      if (!item.fixture.isTest &&
          item.liveHomeGoals != null &&
          item.liveAwayGoals != null &&
          item.resultHomeGoals == null)
        item,
  ];
}

/// «النتائج المباشرة» atop النتائج والاحتساب (2026-10-18): a goal ruled out
/// by VAR that the provider still counts is put right here. Tapping a match
/// opens its running score to correct (`PUT /fixtures/{id}/live-score`):
/// the match card and the live points change at once, and the result sync
/// records the corrected score at full time. The same dialog takes a
/// correction back (`DELETE`). Nothing shows while no match is in play.
class AdminLiveScoreCorrections extends ConsumerWidget {
  const AdminLiveScoreCorrections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    // The admin panel's own read of the month (as «بانتظار النتيجة»): the
    // score shown is the one when the panel opened; the server corrects
    // against the provider's figure of the moment, whatever is shown here.
    final List<CurrentMonthFixtureItemDto> items = switch (ref.watch(
      adminDashboardProvider,
    )) {
      AsyncData<AdminDashboardSnapshot>(:final value) => liveScoresToCorrect(
        value.currentMonthFixtures,
      ),
      _ => const <CurrentMonthFixtureItemDto>[],
    };
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AdminCard(
        key: const Key('admin.results.live'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSectionHeader(
              title: 'النتائج المباشرة (${items.length})',
              subtitle:
                  'هدف أُلغي والمزوّد ما زال يحسبه؟ اضغط المباراة '
                  'وصحّح نتيجتها',
            ),
            for (final CurrentMonthFixtureItemDto item in items)
              // A ListTile paints its ink on the nearest Material; the card's
              // own background would hide it.
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: Key('admin.results.live.${item.fixture.fixtureId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_note_rounded, color: t.gold),
                  title: Text(
                    '${item.fixture.homeTeam ?? 'غير محدد'} '
                    '${item.liveHomeGoals} - ${item.liveAwayGoals} '
                    '${item.fixture.awayTeam ?? 'غير محدد'}',
                    style: context.text.bodyMedium?.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    item.liveFinished == true
                        ? 'انتهت، بانتظار تسجيل النتيجة'
                        : item.liveMinute == null
                        ? 'مباشر'
                        : 'مباشر، الدقيقة ${item.liveMinute}',
                    style: context.text.bodySmall?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _CorrectLiveScoreDialog(item: item),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CorrectLiveScoreDialog extends ConsumerStatefulWidget {
  const _CorrectLiveScoreDialog({required this.item});

  final CurrentMonthFixtureItemDto item;

  @override
  ConsumerState<_CorrectLiveScoreDialog> createState() =>
      _CorrectLiveScoreDialogState();
}

class _CorrectLiveScoreDialogState
    extends ConsumerState<_CorrectLiveScoreDialog> {
  late final TextEditingController _home = TextEditingController(
    text: '${widget.item.liveHomeGoals ?? 0}',
  );
  late final TextEditingController _away = TextEditingController(
    text: '${widget.item.liveAwayGoals ?? 0}',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _home.dispose();
    _away.dispose();
    super.dispose();
  }

  Future<void> _send({required bool clear}) async {
    final int? home = int.tryParse(_home.text.trim());
    final int? away = int.tryParse(_away.text.trim());
    if (!clear && (home == null || away == null)) {
      setState(() => _error = 'اكتب عدد أهداف كل فريق.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(competitionApiProvider);
    final String fixtureId = widget.item.fixture.fixtureId;
    final Result<bool> result = clear
        ? await api.clearLiveScoreCorrection(fixtureId)
        : await api.correctLiveScore(
            fixtureId: fixtureId,
            homeGoals: home!,
            awayGoals: away!,
          );
    if (!mounted) return;
    switch (result) {
      case Ok<bool>():
        ref.invalidate(adminDashboardProvider);
        ref.invalidate(currentMonthFixturesProvider);
        final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
          context,
        );
        Navigator.of(context).pop();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              clear ? 'عادت نتيجة المزوّد' : 'صُحّحت النتيجة المباشرة',
            ),
          ),
        );
      case Err<bool>(:final error):
        setState(() {
          _busy = false;
          _error = ErrorPresenter.message(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final SeasonFixtureCardDto fixture = widget.item.fixture;
    return AlertDialog(
      title: const Text('تصحيح النتيجة المباشرة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تُعرض النتيجة المصحّحة للجميع وتُحتسب بها النقاط، وتُسجَّل '
            'نتيجةً نهائية عند انتهاء المباراة.',
            style: context.text.bodySmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _GoalsField(
                  key: const Key('admin.results.live.home'),
                  controller: _home,
                  label: fixture.homeTeam ?? 'المضيف',
                  enabled: !_busy,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text('-'),
              ),
              Expanded(
                child: _GoalsField(
                  key: const Key('admin.results.live.away'),
                  controller: _away,
                  label: fixture.awayTeam ?? 'الضيف',
                  enabled: !_busy,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              key: const Key('admin.results.live.error'),
              style: context.text.bodySmall?.copyWith(color: t.errorText),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('admin.results.live.clear'),
          onPressed: _busy ? null : () => _send(clear: true),
          child: const Text('إرجاع نتيجة المزوّد'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('رجوع'),
        ),
        FilledButton(
          key: const Key('admin.results.live.save'),
          onPressed: _busy ? null : () => _send(clear: false),
          child: const Text('حفظ التصحيح'),
        ),
      ],
    );
  }
}

class _GoalsField extends StatelessWidget {
  const _GoalsField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      decoration: InputDecoration(labelText: label),
    );
  }
}
