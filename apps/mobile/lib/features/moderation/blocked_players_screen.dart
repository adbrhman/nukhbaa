/// "اللاعبون المحظورون" from the settings (script 225): the players this
/// phone hides, each with the way to lift the block.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import 'blocked_players.dart';

/// The list of blocked players.
class BlockedPlayersScreen extends ConsumerWidget {
  /// Creates the page.
  const BlockedPlayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final Map<String, String> blocked = ref.watch(blockedPlayersProvider);
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('اللاعبون المحظورون', key: Key('blocked.title')),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxAccountWidth,
            ),
            child: blocked.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'لم تحظر أي لاعب. يمكنك حظر لاعب من القائمة بجانب اسمه '
                      'في الترتيب.',
                      key: const Key('blocked.empty'),
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: <Widget>[
                      for (final MapEntry<String, String> entry
                          in blocked.entries)
                        ListTile(
                          key: Key('blocked.item.${entry.key}'),
                          title: Text(entry.value),
                          trailing: TextButton(
                            key: Key('blocked.unblock.${entry.key}'),
                            onPressed: () => unawaited(
                              ref
                                  .read(blockedPlayersProvider.notifier)
                                  .unblock(entry.key),
                            ),
                            child: const Text('إلغاء الحظر'),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
