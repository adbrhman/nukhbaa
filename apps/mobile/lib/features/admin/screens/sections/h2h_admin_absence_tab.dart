/// The admin's tab "الصعود والهبوط" of the head-to-head dashboard (batch 184):
/// relegation for absence in the elite groups (migration 0189). It shows the
/// month's rounds and which of them count, the elite players absent from the
/// latest counted rounds, the substitutes the rules would take, and every
/// seat swap made. The admin can relegate a player by hand, for a reason, and
/// excuse a round that failed for the system's sake. Every rule is the
/// server's: this page shows what it decided and sends the admin's choice.
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
import 'h2h_admin_tabs.dart';

/// `GET /admin/h2h/absence`: the server's current month.
final adminH2hAbsenceProvider = FutureProvider.autoDispose<H2hAbsenceViewDto>((
  ref,
) async {
  return switch (await ref.watch(adminApiProvider).h2hAbsence()) {
    Ok<H2hAbsenceViewDto>(:final value) => value,
    Err<H2hAbsenceViewDto>(:final error) => throw error,
  };
});

/// A player's name, or the neutral word when he has none.
String h2hAbsenceName(H2hAbsencePlayerDto player) {
  final String? name = player.displayName;
  return name == null || name.isEmpty ? h2hUnnamed : name;
}

/// What a seat move was for, in words.
String h2hSeatMoveKindLabel(String kind) => switch (kind) {
  'admin' => 'هبوط يدوي من المشرف',
  _ => 'هبوط بالغياب',
};

/// The rounds of an absence run, in words: `الجولات 2 و3 و4`.
String h2hAbsentRoundsLabel(List<int> rounds) {
  if (rounds.isEmpty) return '';
  if (rounds.length == 1) return 'الجولة ${rounds.first}';
  return 'الجولات ${rounds.join(' و')}';
}

/// The tab itself.
class H2hAdminAbsenceTab extends ConsumerStatefulWidget {
  /// Creates the tab under [header].
  const H2hAdminAbsenceTab({super.key, required this.header});

  /// The dashboard's header, drawn first in the list.
  final List<Widget> header;

  @override
  ConsumerState<H2hAdminAbsenceTab> createState() => _H2hAdminAbsenceTabState();
}

class _H2hAdminAbsenceTabState extends ConsumerState<H2hAdminAbsenceTab> {
  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _reload() {
    ref.invalidate(adminH2hAbsenceProvider);
    // A swap changes the groups and the log, which are other tabs.
    ref.invalidate(adminH2hGroupsProvider);
    ref.invalidate(adminH2hControlsProvider);
  }

  Future<void> _relegate(H2hAbsenceWatchDto row) async {
    final String name = h2hAbsenceName(row.player);
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _ReasonDialog(
        title: 'هبوط $name',
        body:
            'يُنقل $name من مقعده في النخبة من الجولة التالية التي لم تبدأ، '
            'ويجلس مكانه أفضل بديل بحسب القواعد. يحتفظ كل منهما بنقاطه، '
            'ولا يعود $name هذا الشهر. اكتب السبب، فهو يُسجَّل في سجل '
            'الإجراءات.',
        action: 'هبوط',
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final Result<int> result = await ref
        .read(adminApiProvider)
        .relegateH2hPlayer(userId: row.player.userId, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(switch (result) {
      Ok<int>(:final value) => 'هبط $name، والتبديل من الجولة $value',
      Err<int>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
  }

  Future<void> _excuse(H2hAbsenceRoundDto round) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _ReasonDialog(
        title: 'إعفاء الجولة ${round.round}',
        body:
            'تخرج الجولة ${round.round} من حساب الغياب، فلا تُعدّ على أحد '
            'ولا تقطع سلسلة غيابه. لا يغيّر الإعفاء نتائج المواجهات. اكتب '
            'السبب، مثل تعطّل النظام، فهو يُسجَّل في سجل الإجراءات.',
        action: 'إعفاء',
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .excuseH2hRound(roundId: round.roundId, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(switch (result) {
      Ok<bool>(:final value) =>
        value
            ? 'أُعفيت الجولة ${round.round} من حساب الغياب'
            : 'الجولة ${round.round} معفاة من قبل',
      Err<bool>(:final error) => h2hAdminErrorMessage(error),
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<H2hAbsenceViewDto> view = ref.watch(
      adminH2hAbsenceProvider,
    );
    return ListView(
      key: const Key('admin.h2h.absence.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        ...widget.header,
        ...view.when<List<Widget>>(
          loading: () => const <Widget>[
            Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (Object error, _) => <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  Text(
                    error is AppError
                        ? h2hAdminErrorMessage(error)
                        : 'تعذّر تحميل الصعود والهبوط',
                    key: const Key('admin.h2h.absence.error'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
          data: _body,
        ),
      ],
    );
  }

  List<Widget> _body(H2hAbsenceViewDto data) {
    final AppTokens tokens = context.tokens;
    final TextStyle? heading = context.text.titleSmall?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final TextStyle? muted = context.text.bodySmall?.copyWith(
      color: tokens.textSecondary,
    );
    final TextStyle? strong = context.text.bodyMedium?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w600,
    );
    return <Widget>[
      AdminCard(
        key: const Key('admin.h2h.absence.status'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(h2hMonthLabel(data.monthStart), style: heading),
            const SizedBox(height: AppSpacing.xs),
            Text(
              data.active
                  ? 'الهبوط بالغياب يعمل في مجموعات النخبة 1 إلى 4.'
                  : 'الهبوط بالغياب غير فعّال هذا الشهر: يعمل في شهر القرعة '
                        'الجديدة بعد إجرائها.',
              key: const Key('admin.h2h.absence.active'),
              style: muted,
            ),
            if (data.nextRound != null)
              Text('الجولة التالية: ${data.nextRound}', style: muted),
            if (data.relegatesAt != null)
              Text(
                'يُنفَّذ الهبوط قبلها: '
                '${formatTimestamp(context, data.relegatesAt!)}',
                key: const Key('admin.h2h.absence.at'),
                style: muted,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'تنبيه بعد غيابين متتاليين، وهبوط بعد الثالث، بديله أفضل '
              'الأنشط من المجموعة 5 فما فوق. لا هبوط بعد الجولة 19.',
              style: muted,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('اللاعبون الغائبون', style: heading),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'لاعبو النخبة الذين غابوا عن آخر الجولات المحتسبة، الأطول غياباً '
        'أولاً.',
        style: muted,
      ),
      const SizedBox(height: AppSpacing.sm),
      if (data.watch.isEmpty)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'لا غائبين الآن',
            key: Key('admin.h2h.absence.watch.empty'),
            textAlign: TextAlign.center,
          ),
        ),
      for (final H2hAbsenceWatchDto w in data.watch) ...<Widget>[
        AdminCard(
          key: Key('admin.h2h.absence.watch.${w.player.userId}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(h2hAbsenceName(w.player), style: strong),
              Text(
                'المجموعة ${w.group} · غاب عن '
                '${h2hAbsentRoundsLabel(w.absentRounds)}'
                '${w.warned ? ' · أُرسل له تنبيه' : ''}',
                style: muted,
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminSecondaryButton(
                key: Key('admin.h2h.absence.watch.${w.player.userId}.relegate'),
                label: 'هبوط يدوي',
                icon: Icons.south_rounded,
                loading: _busy,
                onPressed: _busy ? null : () => unawaited(_relegate(w)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      const SizedBox(height: AppSpacing.lg),
      Text('الجولات وحساب الغياب', style: heading),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'الجولة المحتسبة بدأت وانتهت مبارياتها ولها مباريات ولم تُعفَ. '
        'غير ذلك لا يُعدّ غياباً.',
        style: muted,
      ),
      const SizedBox(height: AppSpacing.sm),
      if (data.rounds.isEmpty)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'لا جولات معتمدة في هذا الشهر بعد',
            key: Key('admin.h2h.absence.rounds.empty'),
            textAlign: TextAlign.center,
          ),
        ),
      for (final H2hAbsenceRoundDto r in data.rounds) ...<Widget>[
        AdminCard(
          key: Key('admin.h2h.absence.round.${r.roundId}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('الجولة ${r.round} · ${h2hDayLabel(r.day)}', style: strong),
              Text(_roundState(r), style: muted),
              if (r.locked && r.excusedReason == null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                AdminSecondaryButton(
                  key: Key('admin.h2h.absence.round.${r.roundId}.excuse'),
                  label: 'إعفاء الجولة',
                  icon: Icons.healing_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : () => unawaited(_excuse(r)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      const SizedBox(height: AppSpacing.lg),
      Text('البدلاء المرشحون', style: heading),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'الأقل غياباً عن التوقّع، ثم الأعلى نقاطاً، ثم الأكثر إصابات دقيقة، '
        'خلال آخر 30 يوماً. بشرط 5 أيام نشاط وحضور آخر 3 جولات.',
        style: muted,
      ),
      const SizedBox(height: AppSpacing.sm),
      if (data.candidates.isEmpty)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'لا بدلاء مستوفين للشروط الآن',
            key: Key('admin.h2h.absence.candidates.empty'),
            textAlign: TextAlign.center,
          ),
        ),
      for (final (int i, H2hAbsenceCandidateDto c)
          in data.candidates.indexed) ...<Widget>[
        AdminCard(
          key: Key('admin.h2h.absence.candidate.${c.player.userId}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${i + 1}. ${h2hAbsenceName(c.player)}', style: strong),
              Text('المجموعة ${c.group} · ${_facts(c.facts)}', style: muted),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      const SizedBox(height: AppSpacing.lg),
      Text('التبديلات المنفّذة', style: heading),
      const SizedBox(height: AppSpacing.sm),
      if (data.moves.isEmpty)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'لا تبديلات في هذا الشهر',
            key: Key('admin.h2h.absence.moves.empty'),
            textAlign: TextAlign.center,
          ),
        ),
      for (final H2hSeatMoveDto m in data.moves) ...<Widget>[
        AdminCard(
          key: Key('admin.h2h.absence.move.${m.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${h2hAbsenceName(m.out)} ← ${h2hAbsenceName(m.into)}',
                style: strong,
              ),
              Text(
                '${h2hSeatMoveKindLabel(m.kind)} · من الجولة ${m.fromRound} · '
                'بين المجموعة ${m.eliteGroup} والمجموعة ${m.extraGroup}',
                style: muted,
              ),
              if (m.absentRounds.isNotEmpty)
                Text(
                  'غاب عن ${h2hAbsentRoundsLabel(m.absentRounds)}',
                  style: muted,
                ),
              if (m.facts != null)
                Text('البديل: ${_facts(m.facts!)}', style: muted),
              if (m.reason != null && m.reason!.isNotEmpty)
                Text('السبب: ${m.reason}', style: muted),
              Text(
                '${m.decidedBy == null ? 'النظام' : h2hAbsenceName(m.decidedBy!)}'
                ' · ${formatTimestamp(context, m.createdAt)}',
                style: muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }

  static String _roundState(H2hAbsenceRoundDto r) {
    if (r.excusedReason != null) return 'معفاة: ${r.excusedReason}';
    if (!r.locked) return 'لم تبدأ بعد';
    if (!r.counted) return 'لا تُحتسب في الغياب';
    return r.absent == 0
        ? 'محتسبة · لا غائبين'
        : 'محتسبة · غائبون: ${r.absent}';
  }

  static String _facts(H2hAbsenceFactsDto f) =>
      'فاته ${f.missed} · ${f.points} نقطة · ${f.exact} دقيقة · '
      '${f.activeDays} يوم نشاط';
}

/// Asks for the reason of an admin's decision. Pops with the reason, or
/// null when cancelled; the action stays off while the reason is empty.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final String action;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.body),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('admin.h2h.absence.reason'),
              controller: _reason,
              maxLines: 3,
              minLines: 1,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'السبب'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('admin.h2h.absence.reason.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('admin.h2h.absence.reason.ok'),
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
