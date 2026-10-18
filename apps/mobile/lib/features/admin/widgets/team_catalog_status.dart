library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/error/error_presenter.dart';
import '../../competition/teams_providers.dart';

/// Where the club list (`GET /teams`) stands, above a fixture form's team
/// fields. On 2026-10-19 the list had failed to load once (the server was
/// slow after a restart) and stayed failed while other screens held it, so
/// every club the admin typed read «ليس في قائمة الأندية» and the add-club
/// button stayed off, with nothing to say why; only closing the app fixed it.
///
/// Now a failed load is said in plain words with a retry, the list is asked
/// again when a form that needs it opens on a failed load, and a load in
/// progress says so. Nothing shows once the list is in.
class TeamCatalogStatus extends ConsumerStatefulWidget {
  const TeamCatalogStatus({super.key});

  @override
  ConsumerState<TeamCatalogStatus> createState() => _TeamCatalogStatusState();
}

class _TeamCatalogStatusState extends ConsumerState<TeamCatalogStatus> {
  @override
  void initState() {
    super.initState();
    // A load that failed while another screen held the list stays failed:
    // the form that needs it asks again when it opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AsyncValue<List<TeamDto>> state = ref.read(teamCatalogProvider);
      if (state.hasError && !state.hasValue && !state.isLoading) {
        ref.invalidate(teamCatalogProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<TeamDto>> state = ref.watch(teamCatalogProvider);
    if (state.hasValue) return const SizedBox.shrink();
    final t = context.tokens;
    if (state.isLoading || !state.hasError) {
      return Padding(
        key: const Key('admin.teamCatalog.loading'),
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: <Widget>[
            // A still icon, not a spinner: nothing here keeps a frame
            // pending while the request waits.
            Icon(
              Icons.hourglass_empty_rounded,
              size: 16,
              color: t.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'جارٍ تحميل قائمة الأندية…',
                style: TextStyle(
                  fontSize: AppFontSize.s12,
                  color: t.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, size: 16, color: t.errorText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'تعذّر تحميل قائمة الأندية، فلا يُعرف أي نادٍ الآن. '
                  '${ErrorPresenter.messageOf(state.error)}',
                  key: const Key('admin.teamCatalog.failed'),
                  style: TextStyle(
                    fontSize: AppFontSize.s12,
                    color: t.errorText,
                  ),
                ),
              ),
            ],
          ),
          TextButton.icon(
            key: const Key('admin.teamCatalog.retry'),
            onPressed: () => ref.invalidate(teamCatalogProvider),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
