/// The home page's card that brings pushes to the web build (phase 3 of the
/// plan): on an iPhone in a browser tab it says how to add the app to the
/// home screen, where pushes can reach it; in a browser that can show them
/// it turns them on from the player's tap. Hidden everywhere else, on
/// Android, and once the player answered. "Later" hides it for a week on
/// this browser (audit L-05): it used to come back on every visit.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// When the player last chose "later" on the card, on this browser.
abstract interface class WebPushLaterStore {
  /// The moment, or null when never (or unreadable).
  Future<DateTime?> read();

  /// Remembers [at].
  Future<void> write(DateTime at);
}

/// [WebPushLaterStore] over the platform's secure storage. Never throws: a
/// storage that fails only means the card may show again.
final class SecureWebPushLaterStore implements WebPushLaterStore {
  /// Creates the store over [storage].
  const SecureWebPushLaterStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _key = 'nukhba.webPushLaterAt';
  final FlutterSecureStorage _storage;

  @override
  Future<DateTime?> read() async {
    try {
      final String? raw = await _storage.read(key: _key);
      return raw == null ? null : DateTime.tryParse(raw);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(DateTime at) async {
    try {
      await _storage.write(key: _key, value: at.toUtc().toIso8601String());
    } on Object {
      // The card shows again next time; nothing else depends on it.
    }
  }
}

/// [WebPushLaterStore] in memory, for tests.
final class InMemoryWebPushLaterStore implements WebPushLaterStore {
  /// Creates the store holding [at].
  InMemoryWebPushLaterStore([this.at]);

  /// The stored moment.
  DateTime? at;

  @override
  Future<DateTime?> read() async => at;

  @override
  Future<void> write(DateTime at) async {
    this.at = at;
  }
}

/// Where "later" is remembered.
final webPushLaterStoreProvider = Provider<WebPushLaterStore>(
  (ref) => const SecureWebPushLaterStore(),
);

/// How long "later" hides the card.
const Duration webPushLaterFor = Duration(days: 7);

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

  @override
  void initState() {
    super.initState();
    unawaited(_recallLater());
  }

  /// Hides the card when "later" was chosen less than a week ago.
  Future<void> _recallLater() async {
    final DateTime? at = await ref.read(webPushLaterStoreProvider).read();
    if (!mounted || at == null) return;
    if (DateTime.now().toUtc().difference(at.toUtc()) < webPushLaterFor) {
      setState(() => _later = true);
    }
  }

  void _postpone() {
    setState(() => _later = true);
    unawaited(
      ref.read(webPushLaterStoreProvider).write(DateTime.now().toUtc()),
    );
  }

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
                    ? 'لتصلك تذكيرات المباريات: اضغط زر المشاركة في '
                          'Safari، ثم «إضافة إلى الشاشة الرئيسية»، وافتح نُخبة '
                          'من أيقونتها.'
                    : 'يصلك تذكير قبل المباريات، ونتائج توقعاتك.',
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
                      onPressed: _postpone,
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
