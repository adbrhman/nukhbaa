library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_spacing.dart';
import '../../admin_providers.dart';
import '../../widgets/admin_frame_stats_card.dart';
import '../../widgets/admin_retention_card.dart';

/// التحليلات: هل يعود اللاعبون (الهجرة 0069) وسلاسة التطبيق (0070).
///
/// نُقلت البطاقتان كما هما من الرئيسية (2026-10-07): الرئيسية لما يحتاج
/// قراراً اليوم، وهاتان للقراءة المتأنية. كل بطاقة تملك مزوّدها وحالاتها
/// (تحميل، فراغ، خطأ)، فلا يُكرَّر هنا شيء من منطقها.
class AdminAnalyticsSection extends ConsumerWidget {
  const AdminAnalyticsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(adminFrameStatsProvider);
        return ref.refresh(adminRetentionProvider.future);
      },
      child: ListView(
        key: const Key('admin.analytics.scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: const [
          AdminRetentionCard(),
          SizedBox(height: AppSpacing.lg),
          AdminFrameStatsCard(),
        ],
      ),
    );
  }
}
