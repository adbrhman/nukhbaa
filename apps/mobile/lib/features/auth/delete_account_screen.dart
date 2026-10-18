/// A player deletes his own account (audit M-05, script 114), as Google
/// Play requires: what goes and what stays, then a word typed before the
/// button wakes, so no stray tap deletes an account.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_button.dart';
import 'session_controller.dart';

/// The word that wakes the delete button.
const String deleteAccountWord = 'حذف';

/// What deleting the account does, line by line (decision M-05).
const List<String> _consequences = <String>[
  'يُمحى من نُخبة بريدك واسمك وصورتك، ودخولك، وإشعارات هاتفك.',
  'تخرج من كل الترتيبات من لحظتها، ولا تُمنح بعدها أي جائزة.',
  'تبقى توقعاتك ونقاطك السابقة في السجل بلا اسم، كي لا يتغير ترتيب '
      'الأشهر الماضية.',
  'لا يمكن التراجع. ويمكنك التسجيل من جديد ببريدك نفسه كلاعب جديد يبدأ '
      'من الصفر.',
];

/// The delete-account page, opened from the settings.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  /// Creates the page.
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final TextEditingController _word = TextEditingController();
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  bool get _armed => _word.text.trim() == deleteAccountWord;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final Result<void> result = await ref
        .read(sessionControllerProvider.notifier)
        .deleteAccount();
    if (!mounted) return;
    switch (result) {
      case Ok<void>():
        // Signed out already; back to the root, where the sign-in waits.
        Navigator.of(context).popUntil((route) => route.isFirst);
      case Err<void>(:final error):
        setState(() {
          _busy = false;
          _failure = error.code == 'identity.admin_account_kept'
              ? 'حساب المدير لا يُحذف من التطبيق.'
              : 'تعذّر حذف الحساب. تحقق من الاتصال وحاول مرة أخرى.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('حذف الحساب', key: Key('deleteAccount.title')),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxAccountWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                Text(
                  'حذف حسابك نهائي',
                  style: text.titleMedium?.copyWith(
                    color: tokens.errorText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final String line in _consequences)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      line,
                      style: text.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  key: const Key('deleteAccount.word'),
                  controller: _word,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'اكتب «حذف» للتأكيد',
                  ),
                ),
                if (_failure != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _failure!,
                    key: const Key('deleteAccount.failure'),
                    style: text.bodyMedium?.copyWith(color: tokens.errorText),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  key: const Key('deleteAccount.confirm'),
                  label: 'احذف حسابي',
                  variant: AppButtonVariant.danger,
                  loading: _busy,
                  onPressed: _armed && !_busy
                      ? () => unawaited(_delete())
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
