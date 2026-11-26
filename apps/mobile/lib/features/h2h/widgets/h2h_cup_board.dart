// NK336_01
/// لوحة كأس النخبة لكل لاعب ومشرف (`GET /me/h2h-cup/board`): رأس باسم الكأس
/// وشهره، ثم أقسامه مرتبة. للمشارك: مواجهته الآن ومباريات المواجهة، ثم مساره
/// وبقية المسارات، ثم شجرة الأدوار، ثم جدول الأيام. وللمشاهد الترتيب نفسه
/// بلا «مواجهتك الآن» وبـ«المسارات الثلاثة» بدل «مسارك»: كل قسم يعرف من
/// اللوحة وحدها أهو مشارك أم مشاهد.
///
/// **توقع الخصم للخادم.** يصل توقع لاعب آخر بعد انطلاق مباراته فقط؛ قبلها
/// يرسل الخادم جانبًا محجوبًا، فتكتب الأقسام «تظهر بعد انطلاق المباراة» ولا
/// تقرأ الساعة ولا تخمّن شيئًا. لا يُحسب هنا نقاط ولا يُحسم زوج.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../h2h_cup_texts.dart';
import '../h2h_providers.dart';
import '../h2h_texts.dart';
import 'h2h_cup_days.dart';
import 'h2h_cup_now.dart';
import 'h2h_cup_path.dart';
import 'h2h_cup_tree.dart';

/// لوحة الكأس: تحميل، أو رسالة فارغة قبل قيام الكأس، أو الأقسام.
class H2hCupBoardView extends ConsumerWidget {
  /// ينشئ اللوحة.
  const H2hCupBoardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<H2hCupBoardDto> board = ref.watch(h2hCupBoardProvider);
    return board.when(
      loading: () => const Padding(
        key: Key('h2h.cupBoard.loading'),
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => _Message(
        key: const Key('h2h.cupBoard.error'),
        text: h2hCupBoardLoadFailed,
        action: TextButton(
          key: const Key('h2h.cupBoard.retry'),
          onPressed: () => ref.invalidate(h2hCupBoardProvider),
          child: const Text(h2hCupBoardRetry),
        ),
      ),
      data: (H2hCupBoardDto data) {
        if (data.paths.isEmpty) {
          return const _Message(
            key: Key('h2h.cupBoard.empty'),
            text: h2hCupBoardEmpty,
          );
        }
        final AppTokens t = context.tokens;
        final String? month = data.monthStart;
        return Column(
          key: const Key('h2h.cupBoard'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.emoji_events_rounded, color: t.gold),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    h2hCupTitle,
                    key: const Key('h2h.cupBoard.title'),
                    style: context.text.titleMedium?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (month != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  h2hMonthLabel(month),
                  key: const Key('h2h.cupBoard.month'),
                  style: context.text.bodySmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            H2hCupNowView(board: data),
            H2hCupPathsView(board: data),
            H2hCupTreeView(board: data),
            H2hCupDaysView(board: data),
          ],
        );
      },
    );
  }
}

/// A short message in a card: the empty state or a failed read.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, super.key});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}
