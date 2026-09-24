/// The admin dashboard's view of frame smoothness across every device
/// (migration 0070, `GET /admin/frame-stats`).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../admin_providers.dart';
import 'admin_ui_kit.dart';

/// Share of slow frames under which the app reads as smooth.
const double _smoothBelow = 5;

/// Share of slow frames from which it reads as janky.
const double _jankyFrom = 15;

/// Smoothness over the last week: the share of slow and frozen frames, the
/// slowest frame, how many sessions and players it rests on, and the same
/// per build, newest first, so a regression shows against the build that
/// brought it; and the device models that suffer most, each only once
/// several players report it (migration 0071).
class AdminFrameStatsCard extends ConsumerWidget {
  /// Creates the card.
  const AdminFrameStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final AsyncValue<AdminFrameStatsDto> stats = ref.watch(
      adminFrameStatsProvider,
    );
    return AdminCard(
      key: const Key('admin.frameStats'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, color: t.primaryText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'سلاسة التطبيق',
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          switch (stats) {
            AsyncData(:final value) => _Body(stats: value),
            AsyncError() => Text(
              'تعذّر تحميل قياس السلاسة',
              key: const Key('admin.frameStats.error'),
              style: context.text.bodySmall?.copyWith(color: t.error),
            ),
            _ => const LinearProgressIndicator(),
          },
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats});

  final AdminFrameStatsDto stats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final FrameTotalsDto all = stats.overall;
    final TextStyle? muted = context.text.bodySmall?.copyWith(
      color: t.textMuted,
    );
    if (all.frames == 0) {
      return Text(
        'لا تقارير في آخر ${stats.windowDays} أيام بعد. تصل التقارير حين '
        'يغادر المستخدمون التطبيق بعد التحديث.',
        key: const Key('admin.frameStats.empty'),
        style: muted,
      );
    }
    Color verdict(double slow) => slow < _smoothBelow
        ? t.success
        : (slow >= _jankyFrom ? t.error : t.textPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_percent(all.slowPercent)} إطارات بطيئة',
          key: const Key('admin.frameStats.slow'),
          style: context.text.headlineSmall?.copyWith(
            color: verdict(all.slowPercent),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'متجمّدة ${_percent(all.frozenPercent)} • أبطأ إطار '
          '${all.worstFrameMs} ms',
          style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${all.reports} جلسة من ${all.users} مستخدم • آخر '
          '${stats.windowDays} أيام',
          style: muted,
        ),
        if (stats.devices.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'أكثر الأجهزة معاناة',
            style: context.text.labelLarge?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final DeviceTotalsDto d in stats.devices)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                key: Key('admin.frameStats.device.${d.deviceModel}'),
                children: [
                  Expanded(
                    child: Text(
                      d.deviceModel,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    _percent(d.slowPercent),
                    style: context.text.labelMedium?.copyWith(
                      color: verdict(d.slowPercent),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text('${d.users} مستخدم', style: muted),
                ],
              ),
            ),
        ],
        if (stats.builds.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final FrameTotalsDto b in stats.builds)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                key: Key('admin.frameStats.build.${b.build}'),
                children: [
                  Expanded(
                    child: Text(
                      b.build ?? '—',
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                      style: muted,
                    ),
                  ),
                  Text(
                    _percent(b.slowPercent),
                    style: context.text.labelMedium?.copyWith(
                      color: verdict(b.slowPercent),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text('${b.reports} جلسة', style: muted),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

String _percent(double value) {
  final String text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
  return '$text%';
}
