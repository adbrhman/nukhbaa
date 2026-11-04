/// قسم «النشر الرياضي الذكي» في لوحة المشرف (السكربت 209، فوق مسارات
/// السكربت 208 والهجرة 0200). ست تبويبات: المباريات التي تُغطّى، وإعدادات
/// كل منصة، وحالة الحسابات المربوطة، وألوان الأندية، وسجل المنشورات،
/// والأداء.
///
/// فيسبوك وإنستغرام ينشرهما الخادم آلياً عبر Meta Graph API؛ X يُجهَّز فقط
/// (صورة ونص) ويشاركه المشرف من السجل ثم يضغط «تمت المشاركة». كل المنصات
/// متوقفة حتى يشغّلها المشرف، ووضع الخادم (`NUKHBA_PUBLISHER`) ظاهر أعلى
/// القسم: متوقف، أو تجربة لا يُرسل فيها شيء، أو نشر علني.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_radius.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../admin_publisher_providers.dart';
import '../../widgets/admin_ui_kit.dart';
import 'publisher_admin_tabs.dart';

/// The section's tabs, in the menu's order.
enum PublisherTab { matches, settings, accounts, badges, log, performance }

/// [tab]'s label.
String publisherTabLabel(PublisherTab tab, AppLocalizations l10n) =>
    switch (tab) {
      PublisherTab.matches => l10n.publisherTabMatches,
      PublisherTab.settings => l10n.publisherTabSettings,
      PublisherTab.accounts => l10n.publisherTabAccounts,
      PublisherTab.badges => l10n.publisherTabBadges,
      PublisherTab.log => l10n.publisherTabLog,
      PublisherTab.performance => l10n.publisherTabPerformance,
    };

/// [platform]'s name (`facebook`, `instagram`, `x`).
String publisherPlatformLabel(String platform, AppLocalizations l10n) =>
    switch (platform) {
      'facebook' => l10n.publisherPlatformFacebook,
      'instagram' => l10n.publisherPlatformInstagram,
      'x' => l10n.publisherPlatformX,
      _ => platform,
    };

/// Shows [message] at the foot of the page.
void publisherSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Asks before an action; true when the admin confirmed.
Future<bool> publisherConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: <Widget>[
        TextButton(
          key: const Key('admin.publisher.confirm.cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.publisherCancel),
        ),
        FilledButton(
          key: const Key('admin.publisher.confirm.ok'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// The «النشر الرياضي الذكي» section of the admin hub.
class PublisherAdminSection extends ConsumerStatefulWidget {
  /// Creates the section, opened on [initialTab].
  const PublisherAdminSection({
    super.key,
    this.initialTab = PublisherTab.matches,
  });

  /// The tab shown first.
  final PublisherTab initialTab;

  @override
  ConsumerState<PublisherAdminSection> createState() =>
      _PublisherAdminSectionState();
}

class _PublisherAdminSectionState extends ConsumerState<PublisherAdminSection> {
  late PublisherTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<PublisherOverviewDto> overview = ref.watch(
      adminPublisherOverviewProvider,
    );
    final List<Widget> header = <Widget>[
      AdminSectionHeader(
        title: l10n.publisherSectionTitle,
        subtitle: l10n.publisherSectionSubtitle,
      ),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final PublisherTab tab in PublisherTab.values)
            ChoiceChip(
              key: Key('admin.publisher.tab.${tab.name}'),
              label: Text(publisherTabLabel(tab, l10n)),
              selected: _tab == tab,
              onSelected: (_) => setState(() => _tab = tab),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
    ];
    return ListView(
      key: const Key('admin.publisher.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        ...header,
        ...overview.when(
          loading: () => <Widget>[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
          error: (Object error, _) => <Widget>[_LoadError(error: error)],
          data: (PublisherOverviewDto data) => <Widget>[
            PublisherModeBanner(mode: data.mode),
            const SizedBox(height: AppSpacing.md),
            switch (_tab) {
              PublisherTab.matches => PublisherMatchesTab(overview: data),
              PublisherTab.settings => PublisherSettingsTab(overview: data),
              PublisherTab.accounts => PublisherAccountsTab(overview: data),
              PublisherTab.badges => PublisherBadgesTab(overview: data),
              PublisherTab.log => PublisherLogTab(overview: data),
              PublisherTab.performance => PublisherPerformanceTab(
                overview: data,
              ),
            },
          ],
        ),
      ],
    );
  }
}

/// Why the panel could not be read, and a way to try again. While
/// `NUKHBA_PUBLISHER` is off the server answers `publisher.unavailable`:
/// the admin is told what to set rather than shown an error.
class _LoadError extends ConsumerWidget {
  const _LoadError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final AppError appError = ErrorPresenter.asAppError(error);
    final bool off = appError.code == 'publisher.unavailable';
    return AdminCard(
      key: const Key('admin.publisher.loadError'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            off ? l10n.publisherUnavailable : l10n.publisherLoadFailed,
            key: off ? const Key('admin.publisher.unavailable') : null,
            style: context.text.titleSmall?.copyWith(
              color: off ? tokens.textPrimary : tokens.errorText,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!off) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              ErrorPresenter.message(appError),
              style: context.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('admin.publisher.reload'),
              onPressed: () => ref.invalidate(adminPublisherOverviewProvider),
              child: Text(l10n.publisherReload),
            ),
          ),
        ],
      ),
    );
  }
}

/// The server's mode, always in sight: nothing is posted while it is off
/// or a dry run, whatever the platforms' switches say.
class PublisherModeBanner extends StatelessWidget {
  /// Creates the banner for [mode] (`off`, `dry_run`, `on`).
  const PublisherModeBanner({super.key, required this.mode});

  /// The server's `NUKHBA_PUBLISHER`.
  final String mode;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final (Color fill, Color ink, IconData icon, String text) = switch (mode) {
      'on' => (
        tokens.successContainer,
        tokens.textPrimary,
        Icons.campaign_rounded,
        l10n.publisherModeOn,
      ),
      'dry_run' => (
        tokens.goldContainer,
        tokens.textPrimary,
        Icons.science_rounded,
        l10n.publisherModeDryRun,
      ),
      _ => (
        tokens.errorContainer,
        tokens.errorText,
        Icons.pause_circle_rounded,
        l10n.publisherModeOff,
      ),
    };
    return Container(
      key: Key('admin.publisher.mode.$mode'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: fill, borderRadius: AppRadius.brButton),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: ink),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: context.text.bodyMedium?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// «المباريات»: the matches of the coming three days, each covered or not
/// by a switch. Only covered matches are posted about.
class PublisherMatchesTab extends ConsumerStatefulWidget {
  /// Creates the tab.
  const PublisherMatchesTab({super.key, required this.overview});

  /// The panel as last read.
  final PublisherOverviewDto overview;

  @override
  ConsumerState<PublisherMatchesTab> createState() =>
      _PublisherMatchesTabState();
}

class _PublisherMatchesTabState extends ConsumerState<PublisherMatchesTab> {
  bool _coveredOnly = false;

  /// What the admin just set, shown until the panel is read again.
  final Map<String, bool> _pending = <String, bool>{};

  @override
  void didUpdateWidget(PublisherMatchesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.overview, widget.overview)) _pending.clear();
  }

  bool _covered(PublisherCandidateDto match) =>
      _pending[match.fixtureId] ?? match.covered;

  Future<void> _set(PublisherCandidateDto match, bool covered) async {
    setState(() => _pending[match.fixtureId] = covered);
    final Result<bool> result = await ref
        .read(adminApiProvider)
        .setPublisherCoverage(fixtureId: match.fixtureId, covered: covered);
    if (!mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = '${match.homeName} - ${match.awayName}';
    switch (result) {
      case Ok<bool>():
        publisherSnack(
          context,
          covered
              ? l10n.publisherCoverOn(label)
              : l10n.publisherCoverOff(label),
        );
        ref.invalidate(adminPublisherOverviewProvider);
      case Err<bool>(:final error):
        setState(() => _pending.remove(match.fixtureId));
        publisherSnack(context, ErrorPresenter.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final List<PublisherCandidateDto> all = widget.overview.candidates;
    final int covered = all.where(_covered).length;
    final List<PublisherCandidateDto> shown = _coveredOnly
        ? all.where(_covered).toList()
        : all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.publisherMatchesHint,
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.publisherMatchesCount(covered, all.length),
          key: const Key('admin.publisher.matches.count'),
          style: context.text.titleSmall?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            ChoiceChip(
              key: const Key('admin.publisher.matches.all'),
              label: Text(l10n.publisherFilterAll),
              selected: !_coveredOnly,
              onSelected: (_) => setState(() => _coveredOnly = false),
            ),
            ChoiceChip(
              key: const Key('admin.publisher.matches.covered'),
              label: Text(l10n.publisherFilterCovered),
              selected: _coveredOnly,
              onSelected: (_) => setState(() => _coveredOnly = true),
            ),
          ],
        ),
        if (shown.isEmpty)
          AdminEmptyState(
            icon: Icons.sports_soccer_rounded,
            title: all.isEmpty
                ? l10n.publisherMatchesEmpty
                : l10n.publisherMatchesNoneCovered,
          ),
        for (final PublisherCandidateDto match in shown) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _matchRow(context, match),
        ],
      ],
    );
  }

  Widget _matchRow(BuildContext context, PublisherCandidateDto match) {
    final AppTokens tokens = context.tokens;
    final bool covered = _covered(match);
    final String when = match.kickoffAt.isEmpty
        ? ''
        : formatTimestamp(context, match.kickoffAt);
    final String detail = <String>[
      match.leagueName,
      when,
    ].where((String part) => part.isNotEmpty).join(' · ');
    return AdminCard(
      key: Key('admin.publisher.match.${match.fixtureId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${match.homeName} - ${match.awayName}',
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: context.text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(
            key: Key('admin.publisher.cover.${match.fixtureId}'),
            value: covered,
            onChanged: _pending.containsKey(match.fixtureId)
                ? null
                : (bool value) => _set(match, value),
          ),
        ],
      ),
    );
  }
}

/// «الإعدادات»: one card per platform -- on or off, which goals, the final
/// result, the hold, the least gap and the daily cap -- each saved by its
/// own button.
class PublisherSettingsTab extends StatelessWidget {
  /// Creates the tab.
  const PublisherSettingsTab({super.key, required this.overview});

  /// The panel as last read.
  final PublisherOverviewDto overview;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.publisherSettingsHint,
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        for (final String platform in publisherPlatforms)
          for (final PublisherSettingDto setting in overview.settings)
            if (setting.platform == platform) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              PublisherSettingCard(
                key: Key('admin.publisher.setting.$platform'),
                setting: setting,
                mode: overview.mode,
                linked: overview.linked.contains(platform),
              ),
            ],
      ],
    );
  }
}

/// One platform's setting, edited as a draft and saved by its button.
class PublisherSettingCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const PublisherSettingCard({
    super.key,
    required this.setting,
    required this.mode,
    required this.linked,
  });

  /// The setting as the server holds it.
  final PublisherSettingDto setting;

  /// The server's mode: turning a platform on while it is `on` asks first.
  final String mode;

  /// Whether the server holds an account for the platform.
  final bool linked;

  @override
  ConsumerState<PublisherSettingCard> createState() =>
      _PublisherSettingCardState();
}

class _PublisherSettingCardState extends ConsumerState<PublisherSettingCard> {
  late PublisherSettingDto _draft = widget.setting;
  bool _busy = false;
  String? _error;

  String get _platform => widget.setting.platform;

  static bool _same(PublisherSettingDto a, PublisherSettingDto b) =>
      a.enabled == b.enabled &&
      a.goals == b.goals &&
      a.finalResult == b.finalResult &&
      a.holdSeconds == b.holdSeconds &&
      a.minGapSeconds == b.minGapSeconds &&
      a.dailyCap == b.dailyCap;

  bool get _dirty => !_same(_draft, widget.setting);

  @override
  void didUpdateWidget(PublisherSettingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && !_same(oldWidget.setting, widget.setting)) {
      _draft = widget.setting;
    }
  }

  void _edit({
    bool? enabled,
    String? goals,
    bool? finalResult,
    int? holdSeconds,
    int? minGapSeconds,
    int? dailyCap,
  }) {
    final PublisherSettingDto d = _draft;
    setState(() {
      _error = null;
      _draft = PublisherSettingDto(
        platform: d.platform,
        enabled: enabled ?? d.enabled,
        goals: goals ?? d.goals,
        finalResult: finalResult ?? d.finalResult,
        holdSeconds: holdSeconds ?? d.holdSeconds,
        minGapSeconds: minGapSeconds ?? d.minGapSeconds,
        dailyCap: dailyCap ?? d.dailyCap,
      );
    });
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = publisherPlatformLabel(_platform, l10n);
    // A platform turned on while the server posts for real goes public at
    // once: the admin is asked first. X is only prepared, never posted.
    if (_draft.enabled &&
        !widget.setting.enabled &&
        widget.mode == 'on' &&
        _platform != 'x') {
      final bool sure = await publisherConfirm(
        context,
        title: l10n.publisherEnableTitle(name),
        body: l10n.publisherEnableLiveBody(name),
        action: l10n.publisherEnableConfirm,
      );
      if (!sure || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<PublisherSettingDto> result = await ref
        .read(adminApiProvider)
        .savePublisherSetting(_draft);
    if (!mounted) return;
    switch (result) {
      case Ok<PublisherSettingDto>(:final value):
        setState(() {
          _busy = false;
          _draft = value;
        });
        publisherSnack(context, l10n.publisherSaved(name));
        ref.invalidate(adminPublisherOverviewProvider);
      case Err<PublisherSettingDto>(:final error):
        setState(() {
          _busy = false;
          _error = ErrorPresenter.message(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final String p = _platform;
    final int hold = _draft.holdSeconds ~/ 60;
    final int gap = _draft.minGapSeconds ~/ 60;
    final int cap = _draft.dailyCap;
    final String? error = _error;
    final String note = switch (p) {
      'facebook' => l10n.publisherFacebookNote,
      'instagram' => l10n.publisherInstagramNote,
      _ => l10n.publisherXNote,
    };
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  publisherPlatformLabel(p, l10n),
                  style: context.text.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                key: Key('admin.publisher.enabled.$p'),
                value: _draft.enabled,
                onChanged: _busy ? null : (bool v) => _edit(enabled: v),
              ),
            ],
          ),
          Text(
            note,
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          if (p != 'x' && !widget.linked) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.publisherNotLinkedWarning,
              key: Key('admin.publisher.notLinked.$p'),
              style: context.text.bodySmall?.copyWith(color: tokens.errorText),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.publisherGoals,
            style: context.text.labelLarge?.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final (String value, String label) in <(String, String)>[
                ('all', l10n.publisherGoalsAll),
                ('key', l10n.publisherGoalsKey),
                ('none', l10n.publisherGoalsNone),
              ])
                ChoiceChip(
                  key: Key('admin.publisher.goals.$p.$value'),
                  label: Text(label),
                  selected: _draft.goals == value,
                  onSelected: _busy ? null : (_) => _edit(goals: value),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.publisherFinalResult,
                  style: context.text.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              Switch(
                key: Key('admin.publisher.final.$p'),
                value: _draft.finalResult,
                onChanged: _busy ? null : (bool v) => _edit(finalResult: v),
              ),
            ],
          ),
          _Stepper(
            keyName: 'admin.publisher.hold.$p',
            label: l10n.publisherHold,
            value: l10n.publisherMinutes(hold),
            onLess: _busy || hold <= publisherHoldMinMinutes
                ? null
                : () => _edit(holdSeconds: (hold - 1) * 60),
            onMore: _busy || hold >= publisherHoldMaxMinutes
                ? null
                : () => _edit(holdSeconds: (hold + 1) * 60),
          ),
          _Stepper(
            keyName: 'admin.publisher.gap.$p',
            label: l10n.publisherGap,
            value: l10n.publisherMinutes(gap),
            onLess: _busy || gap <= 0
                ? null
                : () => _edit(minGapSeconds: (gap - 1) * 60),
            onMore: _busy || gap >= publisherGapMaxMinutes
                ? null
                : () => _edit(minGapSeconds: (gap + 1) * 60),
          ),
          _Stepper(
            keyName: 'admin.publisher.cap.$p',
            label: l10n.publisherDailyCap,
            value: l10n.publisherCapValue(cap),
            onLess: _busy || cap <= 0 ? null : () => _edit(dailyCap: cap - 1),
            onMore: _busy || cap >= publisherCapMax
                ? null
                : () => _edit(dailyCap: cap + 1),
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AdminErrorBanner(message: error),
          ],
          const SizedBox(height: AppSpacing.md),
          AdminPrimaryButton(
            key: Key('admin.publisher.save.$p'),
            label: l10n.publisherSave,
            icon: Icons.save_rounded,
            loading: _busy,
            onPressed: _dirty && !_busy ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// A number set by a minus and a plus, between bounds the caller checks.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.keyName,
    required this.label,
    required this.value,
    required this.onLess,
    required this.onMore,
  });

  final String keyName;
  final String label;
  final String value;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: context.text.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                Text(
                  value,
                  key: Key('$keyName.value'),
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('$keyName.less'),
            onPressed: onLess,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          IconButton(
            key: Key('$keyName.more'),
            onPressed: onMore,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

/// «الحسابات»: whether the server holds each account, and a check that
/// asks Facebook and Instagram whose account the token opens. The tokens
/// never leave the server; only the account's name comes back.
class PublisherAccountsTab extends ConsumerStatefulWidget {
  /// Creates the tab.
  const PublisherAccountsTab({super.key, required this.overview});

  /// The panel as last read.
  final PublisherOverviewDto overview;

  @override
  ConsumerState<PublisherAccountsTab> createState() =>
      _PublisherAccountsTabState();
}

class _PublisherAccountsTabState extends ConsumerState<PublisherAccountsTab> {
  List<PublisherAccountDto>? _checked;
  bool _busy = false;
  String? _error;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<List<PublisherAccountDto>> result = await ref
        .read(adminApiProvider)
        .publisherAccounts();
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok<List<PublisherAccountDto>>(:final value):
          _checked = value;
        case Err<List<PublisherAccountDto>>(:final error):
          _error = ErrorPresenter.message(error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final List<PublisherAccountDto>? checked = _checked;
    final String? error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.publisherAccountsHint,
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        for (final String platform in publisherPlatforms) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _accountCard(context, platform, checked),
        ],
        if (checked != null && checked.isEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.publisherAccountsNone,
            key: const Key('admin.publisher.accounts.none'),
            style: context.text.bodySmall?.copyWith(color: tokens.errorText),
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AdminErrorBanner(message: error),
        ],
        const SizedBox(height: AppSpacing.md),
        AdminSecondaryButton(
          key: const Key('admin.publisher.accounts.test'),
          label: l10n.publisherTestAccounts,
          icon: Icons.verified_user_rounded,
          loading: _busy,
          onPressed: _busy ? null : _check,
        ),
      ],
    );
  }

  Widget _accountCard(
    BuildContext context,
    String platform,
    List<PublisherAccountDto>? checked,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final bool linked = widget.overview.linked.contains(platform);
    PublisherAccountDto? result;
    for (final PublisherAccountDto account
        in checked ?? const <PublisherAccountDto>[]) {
      if (account.platform == platform) result = account;
    }
    final String vars = switch (platform) {
      'facebook' => 'NUKHBA_META_PAGE_ID, NUKHBA_META_PAGE_TOKEN',
      'instagram' => 'NUKHBA_META_IG_USER_ID, NUKHBA_META_PAGE_TOKEN',
      _ => '',
    };
    final (String status, Color colour) = platform == 'x'
        ? (l10n.publisherXAccount, tokens.textSecondary)
        : linked
        ? (l10n.publisherLinked, tokens.successText)
        : (l10n.publisherNotLinked, tokens.errorText);
    return AdminCard(
      key: Key('admin.publisher.account.$platform'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            publisherPlatformLabel(platform, l10n),
            style: context.text.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            status,
            key: Key('admin.publisher.account.$platform.status'),
            style: context.text.bodyMedium?.copyWith(color: colour),
          ),
          if (platform != 'x' && !linked)
            Text(
              l10n.publisherNeedsVars(vars),
              style: context.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          if (result != null)
            Text(
              result.ok
                  ? l10n.publisherAccountOk(result.detail)
                  : l10n.publisherAccountFailed(result.detail),
              key: Key('admin.publisher.account.$platform.check'),
              style: context.text.bodyMedium?.copyWith(
                color: result.ok ? tokens.successText : tokens.errorText,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
