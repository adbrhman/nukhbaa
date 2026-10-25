/// بطاقة «إصدار التطبيق» في لوحة المشرف (الدفعة 147، الهجرة 0113): أحدث
/// إصدار منشور ورقمه، وأقدم إصدار ما زال مدعومًا، وزرّا رفعه إلى أحدث إصدار
/// أو إلغائه.
///
/// الحد الأدنى دائمًا إصدار منشور: لا يكتب المشرف رقمًا بيده، فلا يمكن أن
/// يُحبس أحد خلف إصدار غير موجود. من كانت نسخته أقدم منه يرى عند فتح
/// التطبيق شاشة «حدِّث نُخبة لتكمل» ولا يكمل قبل التحديث. النسخ المثبّتة قبل
/// هذه الدفعة لا تعرف الحد الأدنى: يصلها الإعلان فقط.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/providers.dart';
import 'admin_ui_kit.dart';

/// أحدث إصدار والحد الأدنى كما يراهما اللاعبون (`GET /app/latest-build`).
/// القراءة الفاشلة تظهر فورًا بلا إعادة محاولة تلقائية.
final appReleaseProvider = FutureProvider.autoDispose<LatestBuildDto>((
  ref,
) async {
  final Result<LatestBuildDto> result = await ref
      .watch(appApiProvider)
      .latestBuild();
  return switch (result) {
    Ok<LatestBuildDto>(:final value) => value,
    Err<LatestBuildDto>(:final error) => throw error,
  };
}, retry: (_, _) => null);

/// البطاقة نفسها.
class AppReleaseCard extends ConsumerStatefulWidget {
  /// ينشئ البطاقة.
  const AppReleaseCard({super.key});

  @override
  ConsumerState<AppReleaseCard> createState() => _AppReleaseCardState();
}

class _AppReleaseCardState extends ConsumerState<AppReleaseCard> {
  bool _busy = false;
  AppError? _error;

  Future<void> _set({required bool toLatest, int? latest}) async {
    if (toLatest) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('admin.appRelease.confirm'),
          title: const Text('إجبار التحديث'),
          content: Text(
            'كل من نسخته أقدم من الإصدار رقم $latest سيرى عند فتح التطبيق '
            'شاشة «يتوفر تحديث جديد» ويبدأ التنزيل وحده، ولن يكمل قبل '
            'التحديث. من نسخته أقدم من شاشة المواجهات (قبل 10 أكتوبر) يرفض '
            'الخادم طلباته برسالة تحديث. إلغاء الحد الأدنى يعيد الجميع إلى '
            'الوضع العادي.',
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('admin.appRelease.cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('admin.appRelease.confirmRaise'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('اجعله الحد الأدنى'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final AdminApi api = ref.read(adminApiProvider);
    final Result<AppUpdatePolicyDto> result = await api.setMinSupportedBuild(
      toLatest: toLatest,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result case Err<AppUpdatePolicyDto>(:final error)) _error = error;
    });
    ref.invalidate(appReleaseProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AsyncValue<LatestBuildDto> release = ref.watch(appReleaseProvider);
    final TextStyle line = TextStyle(color: t.textPrimary);

    return AdminCard(
      key: const Key('admin.appRelease'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AdminSectionHeader(
            title: 'إصدار التطبيق',
            subtitle:
                'رفع الحد الأدنى يجعله أحدث إصدار منشور. ارفعه بعد إصلاح مهم '
                'فقط؛ الإصدارات العادية لا تُجبر أحدًا.',
          ),
          ...switch (release) {
            AsyncData<LatestBuildDto>(:final value) => <Widget>[
              Text(
                value.buildNumber == null
                    ? 'أحدث إصدار: بلا رقم (نُشر قبل هذه الميزة)'
                    : 'أحدث إصدار: رقم ${value.buildNumber}',
                key: const Key('admin.appRelease.latest'),
                style: line,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value.minSupportedBuild == null
                    ? 'لا حد أدنى: لا يُطلب من أحد أن يحدّث'
                    : 'الحد الأدنى: رقم ${value.minSupportedBuild}',
                key: const Key('admin.appRelease.minimum'),
                style: line,
              ),
              const SizedBox(height: AppSpacing.md),
              AdminPrimaryButton(
                key: const Key('admin.appRelease.raise'),
                // Short: the kit's button is one unwrapped row.
                label: 'ارفع الحد الأدنى',
                icon: Icons.system_update_rounded,
                loading: _busy,
                onPressed:
                    _busy ||
                        value.buildNumber == null ||
                        value.buildNumber == value.minSupportedBuild
                    ? null
                    : () => _set(toLatest: true, latest: value.buildNumber),
              ),
              if (value.minSupportedBuild != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                AdminSecondaryButton(
                  key: const Key('admin.appRelease.clear'),
                  label: 'إلغاء الحد الأدنى',
                  icon: Icons.lock_open_rounded,
                  onPressed: _busy ? null : () => _set(toLatest: false),
                ),
              ],
            ],
            AsyncError<LatestBuildDto>() => <Widget>[
              Text(
                'تعذّرت قراءة أحدث إصدار.',
                key: const Key('admin.appRelease.loadError'),
                style: TextStyle(color: t.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              AdminSecondaryButton(
                label: 'إعادة المحاولة',
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(appReleaseProvider),
              ),
            ],
            _ => const <Widget>[LinearProgressIndicator()],
          },
          if (_error case final AppError error) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AdminErrorBanner(
              key: const Key('admin.appRelease.error'),
              message: ErrorPresenter.message(error),
              detail: 'تعذّر حفظ الحد الأدنى',
            ),
          ],
        ],
      ),
    );
  }
}
