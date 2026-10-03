/// قسم «سجل الأخطاء» في لوحة المشرف (migrations 0087, 0088): كل خطأ غير
/// متوقع في الخادم أو التطبيق أو الويب، مجمّعًا في سطر واحد بعدّاد.
///
/// القوائم: جديد، ومتكرر، وحرج، والكل، ولكل قائمة عدّادها. البحث برمز
/// المشكلة الذي يرسله اللاعب يجد خطأه في كل القوائم. صفحة الخطأ تعرض
/// التفاصيل والعيّنات والإصدارات، وتغيّر الحالة والخطورة والمسؤول
/// والملاحظات (يُسجَّل كل تغيير في سجل التدقيق)، وتنسخ تقريرًا جاهزًا
/// للمطوّر. لا يُحذف شيء من هنا.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../widgets/admin_ui_kit.dart';

/// What one list read asks for: the list, or a problem code in every list.
typedef ErrorLogQuery = ({String list, String code});

/// `GET /admin/errors`.
final adminErrorLogProvider = FutureProvider.autoDispose
    .family<AdminErrorListDto, ErrorLogQuery>((ref, query) async {
      final Result<AdminErrorListDto> result = await ref
          .watch(adminApiProvider)
          .errorLog(list: query.list, code: query.code);
      return switch (result) {
        Ok<AdminErrorListDto>(:final value) => value,
        Err<AdminErrorListDto>(:final error) => throw error,
      };
    });

/// `GET /admin/errors/{id}`.
final adminErrorDetailProvider = FutureProvider.autoDispose
    .family<AdminErrorDetailDto, int>((ref, id) async {
      final Result<AdminErrorDetailDto> result = await ref
          .watch(adminApiProvider)
          .errorDetail(id);
      return switch (result) {
        Ok<AdminErrorDetailDto>(:final value) => value,
        Err<AdminErrorDetailDto>(:final error) => throw error,
      };
    });

/// `GET /admin/error-releases`.
final adminErrorReleasesProvider =
    FutureProvider.autoDispose<AdminErrorReleasesDto>((ref) async {
      final Result<AdminErrorReleasesDto> result = await ref
          .watch(adminApiProvider)
          .errorReleases();
      return switch (result) {
        Ok<AdminErrorReleasesDto>(:final value) => value,
        Err<AdminErrorReleasesDto>(:final error) => throw error,
      };
    });

/// Arabic names of the lists, statuses, severities and sources.
abstract final class ErrorLogLabels {
  /// The lists, in the order shown.
  static const List<String> lists = <String>[
    'new',
    'recurring',
    'critical',
    'all',
  ];

  /// The statuses, in the order shown.
  static const List<String> statuses = <String>[
    'new',
    'in_progress',
    'fixed',
    'verified',
    'ignored',
  ];

  /// The severities, most severe first.
  static const List<String> severities = <String>[
    'critical',
    'high',
    'medium',
    'low',
  ];

  /// A list's name.
  static String list(String list) => switch (list) {
    'new' => 'جديد',
    'recurring' => 'متكرر',
    'critical' => 'حرج',
    _ => 'الكل',
  };

  /// A status's name.
  static String status(String status) => switch (status) {
    'new' => 'جديد',
    'in_progress' => 'قيد المعالجة',
    'fixed' => 'تم الإصلاح',
    'verified' => 'تم التحقق',
    'ignored' => 'متجاهَل',
    _ => status,
  };

  /// A severity's name.
  static String severity(String severity) => switch (severity) {
    'critical' => 'حرج',
    'high' => 'عالٍ',
    'medium' => 'متوسط',
    'low' => 'منخفض',
    _ => severity,
  };

  /// A source's name.
  static String source(String source) => switch (source) {
    'server' => 'الخادم',
    'android' => 'أندرويد',
    'ios' => 'آيفون',
    'web' => 'الويب',
    _ => source,
  };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// A time as the admin reads it: local, `2026-10-03 14:05`.
String errorLogTime(DateTime at) {
  final DateTime t = at.toLocal();
  return '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';
}

/// The report the "copy for the developer" button copies: what, where,
/// how often, which builds, the steps the samples show, and the newest
/// stack.
String developerReport(AdminErrorDetailDto detail) {
  final AdminErrorDto e = detail.error;
  final StringBuffer out = StringBuffer()
    ..writeln(
      'خطأ ${e.problemCode} — ${e.errorType}'
      '${e.errorCode == null ? '' : ' (${e.errorCode})'}',
    )
    ..writeln('الرسالة: ${e.message}');
  if (e.locationFile != null) {
    out.writeln(
      'المكان: ${e.locationFile}'
      '${e.locationLine == null ? '' : ':${e.locationLine}'}'
      '${e.locationSymbol == null ? '' : ' (${e.locationSymbol})'}',
    );
  }
  out
    ..writeln(
      'المصدر: ${ErrorLogLabels.source(e.source)} · '
      'الخطورة: ${ErrorLogLabels.severity(e.severity)} · '
      'الحالة: ${ErrorLogLabels.status(e.status)}',
    )
    ..writeln(
      'العدد: ${e.occurrences} مرة، ${e.usersAffected} لاعب · '
      'أول ظهور ${errorLogTime(e.firstSeenAt)} (${e.firstBuild}) · '
      'آخر ظهور ${errorLogTime(e.lastSeenAt)} (${e.lastBuild})',
    );
  if (detail.builds.isNotEmpty) {
    out.writeln(
      'الإصدارات: '
      '${detail.builds.map((b) => '${b.build} ×${b.occurrences}').join('، ')}',
    );
  }
  if (detail.samples.isNotEmpty) {
    out.writeln('خطوات الظهور (من العيّنات):');
    var i = 1;
    for (final AdminErrorSampleDto s in detail.samples) {
      final List<String> parts = <String>[
        errorLogTime(s.occurredAt),
        s.build,
        if (s.route != null) s.route!,
        if (s.requestId != null) 'طلب ${s.requestId}',
        if (s.device != null) s.device!,
        if (s.os != null) s.os!,
        if (s.browser != null) s.browser!,
        if (s.requestInput != null) 'المدخلات ${s.requestInput}',
      ];
      out.writeln('$i) ${parts.join(' · ')}');
      i++;
    }
    final String? stack = detail.samples.first.stack;
    if (stack != null && stack.trim().isNotEmpty) {
      out
        ..writeln('Stack (أحدث عيّنة):')
        ..writeln(stack.trim());
    }
  }
  if (e.adminNotes != null && e.adminNotes!.trim().isNotEmpty) {
    out.writeln('ملاحظات المشرف: ${e.adminNotes}');
  }
  return out.toString().trim();
}

/// The "error log" section of the admin hub.
class ErrorLogSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const ErrorLogSection({super.key});

  @override
  ConsumerState<ErrorLogSection> createState() => _ErrorLogSectionState();
}

class _ErrorLogSectionState extends ConsumerState<ErrorLogSection> {
  final TextEditingController _code = TextEditingController();
  String _list = 'new';
  String _searched = '';
  int? _selectedId;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  ErrorLogQuery get _query => (list: _list, code: _searched);

  void _search() {
    setState(() {
      _searched = _code.text.trim().toUpperCase();
      _selectedId = null;
    });
  }

  void _clearSearch() {
    _code.clear();
    setState(() {
      _searched = '';
      _selectedId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<AdminErrorListDto> page = ref.watch(
      adminErrorLogProvider(_query),
    );
    final int? selectedId = _selectedId;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminErrorReleasesProvider);
        ref.invalidate(adminErrorLogProvider(_query));
        try {
          await ref.read(adminErrorLogProvider(_query).future);
        } on Object {
          // The list shows the failure with its retry button.
        }
      },
      child: ListView(
        key: const Key('admin.errors.list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: <Widget>[
          const AdminSectionHeader(
            title: 'سجل الأخطاء',
            subtitle:
                'كل خطأ غير متوقع في الخادم أو التطبيق أو الويب، في سطر واحد '
                'بعدّاد. ابحث برمز المشكلة الذي يرسله اللاعب.',
          ),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AdminTextField(
                  key: const Key('admin.errors.codeField'),
                  controller: _code,
                  hint: 'رمز المشكلة الذي أرسله اللاعب',
                  prefixIcon: Icons.search_rounded,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AdminSecondaryButton(
                        key: const Key('admin.errors.search'),
                        label: 'بحث بالرمز',
                        icon: Icons.search_rounded,
                        onPressed: _search,
                      ),
                    ),
                    if (_searched.isNotEmpty) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        key: const Key('admin.errors.clearSearch'),
                        tooltip: 'إلغاء البحث',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          page.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (Object error, _) => AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    error is AppError
                        ? ErrorPresenter.message(error)
                        : 'تعذّر تحميل سجل الأخطاء',
                    style: TextStyle(color: tokens.error),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(adminErrorLogProvider(_query)),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (AdminErrorListDto data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_searched.isEmpty)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      for (final String list in ErrorLogLabels.lists)
                        ChoiceChip(
                          key: Key('admin.errors.tab.$list'),
                          label: Text(
                            '${ErrorLogLabels.list(list)} '
                            '(${_count(data, list)})',
                          ),
                          selected: _list == list,
                          onSelected: (_) => setState(() {
                            _list = list;
                            _selectedId = null;
                          }),
                        ),
                    ],
                  )
                else
                  Text(
                    'نتائج الرمز $_searched',
                    key: const Key('admin.errors.searchTitle'),
                    style: context.text.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                if (data.errors.isEmpty)
                  const AdminEmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'لا توجد أخطاء هنا',
                  )
                else
                  for (final AdminErrorDto error in data.errors) ...<Widget>[
                    _ErrorRow(
                      key: Key('admin.errors.row.${error.id}'),
                      error: error,
                      selected: error.id == selectedId,
                      onTap: () => setState(
                        () => _selectedId = error.id == selectedId
                            ? null
                            : error.id,
                      ),
                    ),
                    if (error.id == selectedId)
                      _ErrorDetail(
                        key: Key('admin.errors.detail.${error.id}'),
                        id: error.id,
                        admins: data.admins,
                        onChanged: () =>
                            ref.invalidate(adminErrorLogProvider(_query)),
                      ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ReleasesCard(),
        ],
      ),
    );
  }

  static int _count(AdminErrorListDto data, String list) => switch (list) {
    'new' => data.fresh,
    'recurring' => data.recurring,
    'critical' => data.critical,
    _ => data.all,
  };
}

/// The errors of each recent build, and the files most come from.
class _ReleasesCard extends ConsumerWidget {
  const _ReleasesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<AdminErrorReleasesDto> summary = ref.watch(
      adminErrorReleasesProvider,
    );
    final TextStyle? line = context.text.bodySmall?.copyWith(
      color: tokens.textSecondary,
    );
    return AdminCard(
      key: const Key('admin.errors.releases'),
      child: summary.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (Object error, _) => Text(
          error is AppError
              ? ErrorPresenter.message(error)
              : 'تعذّر تحميل ملخّص الإصدارات',
          style: TextStyle(color: tokens.error),
        ),
        data: (AdminErrorReleasesDto data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'ملخّص الإصدارات',
              style: context.text.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (data.releases.isEmpty)
              Text('لا أخطاء في أي إصدار بعد', style: line)
            else
              // The build and the file get a line of their own: a Latin
              // run at the start of an Arabic line is reordered by bidi.
              for (final AdminErrorReleaseDto r in data.releases)
                _SummaryEntry(
                  key: Key('admin.errors.release.${r.build}'),
                  title: r.build,
                  detail:
                      '${r.errors} خطأ'
                      '${r.critical > 0 ? ' (${r.critical} حرج)' : ''} · '
                      '${r.occurrences} مرة · آخر ظهور '
                      '${errorLogTime(r.lastSeenAt)}',
                ),
            if (data.files.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                'أكثر الملفات تسببًا بالأخطاء',
                style: context.text.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final AdminErrorFileDto f in data.files)
                _SummaryEntry(
                  title: f.file,
                  detail: '${f.errors} خطأ · ${f.occurrences} مرة',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One entry of the release summary: a build or a file, then its counts.
class _SummaryEntry extends StatelessWidget {
  const _SummaryEntry({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextStyle? line = context.text.bodySmall?.copyWith(
      color: tokens.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: line?.copyWith(color: tokens.textPrimary)),
          Text(detail, style: line),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    super.key,
    required this.error,
    required this.selected,
    required this.onTap,
  });

  final AdminErrorDto error;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String where = error.locationFile == null
        ? ''
        : '\n${error.locationFile}'
              '${error.locationLine == null ? '' : ':${error.locationLine}'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      // A ListTile paints its ink on the nearest Material; the card's own
      // background would hide it, so the tile gets a Material of its own.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: onTap,
          selected: selected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: error.severity == 'critical'
                  ? tokens.error
                  : tokens.border,
            ),
          ),
          title: Text(
            error.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${error.problemCode} · ${ErrorLogLabels.source(error.source)} · '
            '${ErrorLogLabels.severity(error.severity)} · '
            '${ErrorLogLabels.status(error.status)}\n'
            '${error.occurrences} مرة · ${error.usersAffected} لاعب · '
            'آخر ظهور ${errorLogTime(error.lastSeenAt)} · ${error.lastBuild}'
            '$where',
          ),
          isThreeLine: true,
        ),
      ),
    );
  }
}

class _ErrorDetail extends ConsumerStatefulWidget {
  const _ErrorDetail({
    super.key,
    required this.id,
    required this.admins,
    required this.onChanged,
  });

  final int id;
  final List<AdminRefDto> admins;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ErrorDetail> createState() => _ErrorDetailState();
}

class _ErrorDetailState extends ConsumerState<_ErrorDetail> {
  final TextEditingController _notes = TextEditingController();
  String? _status;
  String? _severity;
  String? _assignee;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _load(AdminErrorDto error) {
    if (_loaded) return;
    _loaded = true;
    _status = error.status;
    _severity = error.severity;
    _assignee = error.assigneeId ?? '';
    _notes.text = error.adminNotes ?? '';
  }

  Future<void> _save(AdminErrorDto current) async {
    final String notes = _notes.text.trim();
    final AdminErrorUpdateDto change = AdminErrorUpdateDto(
      status: _status == current.status ? null : _status,
      severity: _severity == current.severity ? null : _severity,
      assigneeId: _assignee == (current.assigneeId ?? '') ? null : _assignee,
      notes: notes == (current.adminNotes ?? '') ? null : notes,
    );
    if (change.toJson().isEmpty) {
      setState(() => _error = 'لم يتغيّر شيء');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<AdminErrorDetailDto> result = await ref
        .read(adminApiProvider)
        .updateError(widget.id, change);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok<AdminErrorDetailDto>():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم الحفظ')));
        // The chips and the notes already hold what was saved; the page
        // re-reads the rest (counts, samples) without resetting them.
        ref.invalidate(adminErrorDetailProvider(widget.id));
        widget.onChanged();
      case Err<AdminErrorDetailDto>(:final error):
        setState(() => _error = ErrorPresenter.message(error));
    }
  }

  void _copy(AdminErrorDetailDto detail) {
    unawaited(Clipboard.setData(ClipboardData(text: developerReport(detail))));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('نُسخ التقرير للمطوّر')));
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<AdminErrorDetailDto> detail = ref.watch(
      adminErrorDetailProvider(widget.id),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AdminCard(
        child: detail.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (Object error, _) => Text(
            error is AppError
                ? ErrorPresenter.message(error)
                : 'تعذّر تحميل الخطأ',
            style: TextStyle(color: tokens.error),
          ),
          data: (AdminErrorDetailDto data) {
            final AdminErrorDto e = data.error;
            _load(e);
            final String? error = _error;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SelectableText(
                  '${e.errorType}'
                  '${e.errorCode == null ? '' : ' · ${e.errorCode}'}\n'
                  '${e.message}',
                  style: context.text.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'أول ظهور ${errorLogTime(e.firstSeenAt)} (${e.firstBuild}) · '
                  'آخر ظهور ${errorLogTime(e.lastSeenAt)} (${e.lastBuild})'
                  '${e.reopenedCount > 0 ? ' · عاد ${e.reopenedCount} مرة بعد الإصلاح' : ''}',
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('الحالة', style: context.text.labelLarge),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final String s in ErrorLogLabels.statuses)
                      ChoiceChip(
                        key: Key('admin.errors.status.$s'),
                        label: Text(ErrorLogLabels.status(s)),
                        selected: _status == s,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _status = s),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('الخطورة', style: context.text.labelLarge),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final String s in ErrorLogLabels.severities)
                      ChoiceChip(
                        key: Key('admin.errors.severity.$s'),
                        label: Text(ErrorLogLabels.severity(s)),
                        selected: _severity == s,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _severity = s),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('المسؤول', style: context.text.labelLarge),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: <Widget>[
                    ChoiceChip(
                      key: const Key('admin.errors.assignee.none'),
                      label: const Text('بلا مسؤول'),
                      selected: _assignee == '',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _assignee = ''),
                    ),
                    for (final AdminRefDto admin in widget.admins)
                      ChoiceChip(
                        key: Key('admin.errors.assignee.${admin.id}'),
                        label: Text(
                          admin.displayName.isEmpty
                              ? admin.id
                              : admin.displayName,
                        ),
                        selected: _assignee == admin.id,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _assignee = admin.id),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AdminTextField(
                  key: const Key('admin.errors.notes'),
                  controller: _notes,
                  hint: 'ملاحظات المشرف',
                  prefixIcon: Icons.notes_rounded,
                  enabled: !_busy,
                ),
                if (error != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    error,
                    key: const Key('admin.errors.error'),
                    style: TextStyle(color: tokens.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AdminPrimaryButton(
                  key: const Key('admin.errors.save'),
                  label: 'حفظ',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : () => unawaited(_save(e)),
                ),
                const SizedBox(height: AppSpacing.sm),
                AdminSecondaryButton(
                  key: const Key('admin.errors.copyReport'),
                  label: 'نسخ تقرير للمطوّر',
                  icon: Icons.copy_rounded,
                  onPressed: () => _copy(data),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'آخر ${data.samples.length} عيّنات',
                  style: context.text.labelLarge,
                ),
                for (final AdminErrorSampleDto s in data.samples)
                  // ExpansionTile draws a ListTile, which paints on the
                  // nearest Material; the card's background would hide it.
                  Material(
                    type: MaterialType.transparency,
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        '${errorLogTime(s.occurredAt)} · ${s.build}'
                        '${s.route == null ? '' : ' · ${s.route}'}',
                      ),
                      subtitle: Text(
                        <String>[
                          if (s.userName != null) s.userName!,
                          if (s.device != null) s.device!,
                          if (s.os != null) s.os!,
                          if (s.browser != null) s.browser!,
                          if (s.requestId != null) 'طلب ${s.requestId}',
                        ].join(' · '),
                      ),
                      children: <Widget>[
                        SelectableText(
                          <String>[
                            s.message,
                            if (s.requestInput != null) s.requestInput!,
                            if (s.stack != null) s.stack!,
                          ].join('\n\n'),
                          style: context.text.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (data.builds.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Text('الإصدارات', style: context.text.labelLarge),
                  for (final AdminErrorBuildDto b in data.builds)
                    _SummaryEntry(
                      title: b.build,
                      detail:
                          '${b.occurrences} مرة · '
                          'آخر ظهور ${errorLogTime(b.lastSeenAt)}',
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
