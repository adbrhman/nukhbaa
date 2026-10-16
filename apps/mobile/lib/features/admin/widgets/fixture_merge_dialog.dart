/// دمج نسخة مكررة من مباراة في النسخة التي تبقى (script 95، الترحيل 0176).
///
/// أُضيفت مباريات مرتين في 2026-10-15/16، فتوقّع بعض اللاعبين نسخة وبعضهم
/// الأخرى، وإخفاء نسخة أخفى توقّعات أصحابها معها. من سطر النسخة المكررة
/// يُفتح هذا الحوار: يعرض نسخ المباراة نفسها، ويختار المشرف النسخة الظاهرة
/// التي تبقى، فيرى قبل التنفيذ ما سيُنقل وما يبقى، ثم يدمج. الدمج كله في
/// الخادم في معاملة واحدة (`POST /admin/fixtures/{id}/merge`).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared/shared.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/providers.dart';
import 'admin_ui_kit.dart';

/// What a merge would do, line by line, for the preview.
List<String> fixtureMergePreviewLines(FixtureMergeReportDto report) {
  final int keptDouble = report.doublesMoved;
  return <String>[
    report.moved == 0
        ? 'لا توقّع يُنقل من هذه النسخة.'
        : 'يُنقل ${report.moved} من التوقعات إلى النسخة التي تبقى كما هي'
              '${keptDouble > 0 ? '، منها $keptDouble مضاعفة' : ''}.',
    if (report.doublesDropped > 0)
      'يُنقل ${report.doublesDropped} بلا مضاعفة: لأصحابها مضاعفة أخرى في '
          'يوم المباراة.',
    if (report.bothPredicted > 0)
      'يبقى ${report.bothPredicted}: أصحابها توقّعوا النسختين، فيبقى '
          'توقّعهم على النسخة التي تبقى.',
    if (report.late > 0) 'يبقى ${report.late}: أُرسلت بعد بداية المباراة.',
    if (report.notParticipant > 0)
      'يبقى ${report.notParticipant}: أصحابها ليسوا في موسم النسخة التي '
          'تبقى.',
    'ثم تُخفى هذه النسخة نهائيًا ولا تُظهَر بعد ذلك.',
    if (report.keptHasResult && report.moved > 0)
      'وتُحتسب نقاط المباراة من جديد.',
  ];
}

/// The banner after a merge.
String fixtureMergeResultMessage(FixtureMergeReportDto report) {
  final StringBuffer text = StringBuffer(
    'دُمجت النسخة: نُقل ${report.moved} من التوقعات',
  );
  if (report.doublesDropped > 0) {
    text.write('، ${report.doublesDropped} منها بلا مضاعفة');
  }
  if (report.keptHasResult && report.moved > 0) {
    text.write(
      report.rescored
          ? '، واحتُسبت النقاط'
          : '، وتُحتسب النقاط في الدورة التالية',
    );
  }
  text.write('.');
  return text.toString();
}

/// Opens the merge of [fixture]; answers the report when it was merged.
Future<FixtureMergeReportDto?> showFixtureMergeDialog(
  BuildContext context, {
  required SeasonFixtureCardDto fixture,
}) => showDialog<FixtureMergeReportDto>(
  context: context,
  builder: (BuildContext _) => FixtureMergeDialog(fixture: fixture),
);

/// يدمج نسخة مكررة من مباراة في النسخة التي تبقى.
class FixtureMergeDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for the copy [fixture].
  const FixtureMergeDialog({super.key, required this.fixture});

  /// The copy to merge away.
  final SeasonFixtureCardDto fixture;

  @override
  ConsumerState<FixtureMergeDialog> createState() => _FixtureMergeDialogState();
}

class _FixtureMergeDialogState extends ConsumerState<FixtureMergeDialog> {
  List<FixtureCopyDto>? _copies;
  String? _keptId;
  FixtureMergeReportDto? _preview;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Result<FixtureCopiesDto> result = await ref
        .read(adminApiProvider)
        .fixtureCopies(widget.fixture.fixtureId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok<FixtureCopiesDto>(:final value):
          _copies = <FixtureCopyDto>[
            for (final FixtureCopyDto c in value.copies)
              if (!c.isSelf) c,
          ];
        case Err<FixtureCopiesDto>(:final error):
          _error = ErrorPresenter.message(error);
      }
    });
  }

  Future<void> _pick(FixtureCopyDto copy) async {
    setState(() {
      _keptId = copy.fixtureId;
      _preview = null;
      _error = null;
      _busy = true;
    });
    final Result<FixtureMergeReportDto> result = await ref
        .read(adminApiProvider)
        .mergeFixture(
          duplicateId: widget.fixture.fixtureId,
          keptId: copy.fixtureId,
          apply: false,
        );
    if (!mounted || _keptId != copy.fixtureId) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok<FixtureMergeReportDto>(:final value):
          _preview = value;
        case Err<FixtureMergeReportDto>(:final error):
          _error = ErrorPresenter.message(error);
      }
    });
  }

  Future<void> _merge() async {
    final String? kept = _keptId;
    if (kept == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<FixtureMergeReportDto> result = await ref
        .read(adminApiProvider)
        .mergeFixture(
          duplicateId: widget.fixture.fixtureId,
          keptId: kept,
          apply: true,
        );
    if (!mounted) return;
    switch (result) {
      case Ok<FixtureMergeReportDto>(:final value):
        Navigator.of(context).pop(value);
      case Err<FixtureMergeReportDto>(:final error):
        setState(() {
          _busy = false;
          _error = ErrorPresenter.message(error);
        });
    }
  }

  String _copyLine(FixtureCopyDto copy) {
    final DateTime? kickoff = DateTime.tryParse(copy.kickoffAt)?.toLocal();
    final String locale = Localizations.localeOf(context).toString();
    return <String>[
      if (kickoff != null)
        '${intl.DateFormat('d MMMM', locale).format(kickoff)} - '
            '${intl.DateFormat.jm(locale).format(kickoff)}',
      '${copy.predictions} توقّع',
      if (copy.hasResult) 'لها نتيجة',
      if (copy.hidden) 'مخفية',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final List<FixtureCopyDto>? copies = _copies;
    final FixtureMergeReportDto? preview = _preview;
    final String? error = _error;
    final bool anyVisible =
        copies != null && copies.any((FixtureCopyDto c) => !c.hidden);
    return AlertDialog(
      key: const Key('admin.merge.dialog'),
      title: Text(
        'دمج ${widget.fixture.homeTeam ?? ''} × '
        '${widget.fixture.awayTeam ?? ''}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (copies == null && error == null)
              const LinearProgressIndicator()
            else if (copies != null && !anyVisible)
              const Text(
                'لا نسخة ظاهرة أخرى لهذه المباراة تُدمج فيها. إن كانت النسخة '
                'الأخرى هي المخفية فادمجها هي في هذه من سطرها.',
                key: Key('admin.merge.none'),
              )
            else if (copies != null) ...<Widget>[
              const Text('اختر النسخة التي تبقى:'),
              const SizedBox(height: AppSpacing.xs),
              for (final FixtureCopyDto copy in copies)
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    key: Key('admin.merge.copy.${copy.fixtureId}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: !copy.hidden && !_busy,
                    leading: Icon(
                      _keptId == copy.fixtureId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text('${copy.homeTeam} × ${copy.awayTeam}'),
                    subtitle: Text(_copyLine(copy)),
                    onTap: () => _pick(copy),
                  ),
                ),
            ],
            if (preview != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              for (final String line in fixtureMergePreviewLines(preview))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    line,
                    style: context.text.bodyMedium?.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              AdminErrorBanner(
                key: const Key('admin.merge.error'),
                message: error,
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('admin.merge.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('admin.merge.confirm'),
          onPressed: _busy || preview == null ? null : _merge,
          child: _busy && preview != null
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ادمج'),
        ),
      ],
    );
  }
}
