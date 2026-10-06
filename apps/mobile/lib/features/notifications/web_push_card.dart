/// The home page's card that brings pushes to the web build (phase 3 of the
/// plan): on an iPhone in a browser tab it says how to add the app to the
/// home screen, where pushes can reach it; in a browser that can show them
/// it turns them on from the player's tap. Hidden everywhere else, on
/// Android, and once the player answered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/notifications/web_push_platform.dart';
import '../../core/providers.dart';

/// The browser this build runs in.
final webPushPlatformProvider = Provider<WebPushPlatform>(
  (ref) => webPushPlatform,
);

/// Registers this browser for pushes once the player allowed them; true
/// when it did.
final webPushRegistrarProvider = Provider<Future<bool> Function()>(
  (ref) => ref.watch(pushTokenServiceProvider).registerWebDevice,
);

/// The card.
class WebPushCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const WebPushCard({super.key});

  @override
  ConsumerState<WebPushCard> createState() => _WebPushCardState();
}

class _WebPushCardState extends ConsumerState<WebPushCard> {
  bool _later = false;
  bool _busy = false;
  String? _outcome;

  Future<void> _enable() async {
    final WebPushPlatform platform = ref.read(webPushPlatformProvider);
    final Future<bool> Function() register = ref.read(webPushRegistrarProvider);
    setState(() => _busy = true);
    // First, straight from the tap: a browser asks only then.
    final String answer = await platform.requestPermission();
    final bool registered = answer == 'granted' && await register();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = registered
          ? 'ستصلك الإشعارات على هذا الجهاز.'
          : answer == 'denied'
          ? 'لم تسمح بالإشعارات. يمكنك السماح بها من إعدادات المتصفح.'
          : 'تعذّر تفعيل الإشعارات الآن. حاول لاحقاً.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? outcome = _outcome;
    final WebPushOffer offer = webPushOfferFor(
      ref.watch(webPushPlatformProvider),
    );
    if (_later || (offer == WebPushOffer.none && outcome == null)) {
      return const SizedBox.shrink();
    }
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final TextStyle? line = text.bodyMedium?.copyWith(
      color: tokens.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        key: const Key('home.webPush'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: AppRadius.brCard,
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.notifications_active_outlined,
                  color: tokens.primaryText,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    offer == WebPushOffer.install
                        ? 'الإشعارات على iPhone'
                        : 'فعّل الإشعارات',
                    style: text.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (outcome != null)
              Text(outcome, key: const Key('home.webPush.outcome'), style: line)
            else ...<Widget>[
              Text(
                offer == WebPushOffer.install
                    ? 'لتصلك تذكيرات المباريات والتحديات: اضغط زر المشاركة في '
                          'Safari، ثم «إضافة إلى الشاشة الرئيسية»، وافتح نُخبة '
                          'من أيقونتها.'
                    : 'يصلك تذكير قبل المباريات، وتحديات أصدقائك ونتائجها.',
                key: const Key('home.webPush.message'),
                style: line,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  if (offer == WebPushOffer.enable) ...<Widget>[
                    Expanded(
                      child: FilledButton(
                        key: const Key('home.webPush.enable'),
                        onPressed: _busy ? null : _enable,
                        child: const Text('فعّل'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('home.webPush.later'),
                      onPressed: () => setState(() => _later = true),
                      child: const Text('لاحقاً'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
