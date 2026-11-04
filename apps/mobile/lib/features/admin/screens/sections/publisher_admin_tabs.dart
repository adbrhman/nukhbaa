/// تبويبات «ألوان الأندية» و«السجل» و«الأداء» من قسم «النشر الرياضي
/// الذكي» (السكربت 209).
///
/// لا شعار لأي نادٍ (قرار المالك 2026-11-04): كل نادٍ شارة دائرية بلونه
/// واسمه، ونادٍ بلا لون مضبوط يُرسم بكحلي نُخبة. منشور X يُشارك من هنا عبر
/// نافذة المشاركة في الهاتف ثم يُسجَّل «تمت المشاركة». منشور «غير مؤكد»
/// ربما ظهر على المنصة: يُنبَّه المشرف قبل إعادته.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/format/timestamps.dart';
import '../../../../core/providers.dart';
import '../../../../core/ui/share_picture.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../competition/teams_providers.dart';
import '../../admin_publisher_providers.dart';
import '../../widgets/admin_ui_kit.dart';
import 'publisher_admin_section.dart';

/// Nukhba's navy: a club with no colour set, and the dark ink on a light
/// disc (`ClubBadge.defaultFill`).
const Color _navy = Color(0xFF071426);

/// The colours offered at a tap; any other is typed.
const List<String> _swatches = <String>[
  '#1978D1',
  '#6CABDD',
  '#D71920',
  '#FFDD00',
  '#00843D',
  '#000000',
  '#FFFFFF',
  '#5B2C83',
  '#F58220',
  '#071426',
];

/// `#RRGGBB` as a colour; navy for anything else.
Color publisherColourOf(String hex) => isPublisherColour(hex)
    ? Color(0xFF000000 | int.parse(hex.substring(1), radix: 16))
    : _navy;

double _contrast(double a, double b) =>
    ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);

/// The one of white and navy that reads better on [fill] (WCAG 2), as the
/// server picks it (`ClubBadge.inkFor`).
Color publisherInkOn(Color fill) {
  final double background = fill.computeLuminance();
  final double onWhite = _contrast(background, 1);
  final double onNavy = _contrast(background, _navy.computeLuminance());
  return onWhite >= onNavy ? const Color(0xFFFFFFFF) : _navy;
}

/// The words on a club's disc when none are set: a one-word name that
/// starts with «ال» and is longer than five letters loses it, as on the
/// server (`ClubBadge.shortLabel`).
String publisherShortLabel(String clubName) {
  final String name = clubName.trim();
  if (!name.contains(' ') && name.startsWith('ال') && name.length > 5) {
    return name.substring(2);
  }
  return name;
}

/// A club's disc as the pictures draw it.
class PublisherBadgeDisc extends StatelessWidget {
  /// Creates the disc.
  const PublisherBadgeDisc({
    super.key,
    required this.fill,
    required this.label,
    this.size = 56,
  });

  /// `#RRGGBB`.
  final String fill;

  /// The words on it.
  final String label;

  /// Its diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color colour = publisherColourOf(fill);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: Border.all(color: context.tokens.border),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          // The disc keeps its size at any text scale: its words shrink
          // to fit it, as on the picture.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: publisherInkOn(colour),
            fontWeight: FontWeight.w800,
            fontSize: size * 0.28,
          ),
        ),
      ),
    );
  }
}

/// «ألوان الأندية»: an editor (the club, its colour, the words on its
/// disc) above the clubs already set.
class PublisherBadgesTab extends ConsumerStatefulWidget {
  /// Creates the tab.
  const PublisherBadgesTab({super.key, required this.overview});

  /// The panel as last read.
  final PublisherOverviewDto overview;

  @override
  ConsumerState<PublisherBadgesTab> createState() => _PublisherBadgesTabState();
}

class _PublisherBadgesTabState extends ConsumerState<PublisherBadgesTab> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _colour = TextEditingController();
  final TextEditingController _label = TextEditingController();
  String? _teamId;
  String _teamName = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _colour.dispose();
    _label.dispose();
    super.dispose();
  }

  PublisherBadgeDto? _badgeOf(String teamId) {
    for (final PublisherBadgeDto badge in widget.overview.badges) {
      if (badge.teamId == teamId) return badge;
    }
    return null;
  }

  void _pick(String teamId, String teamName) {
    final PublisherBadgeDto? badge = _badgeOf(teamId);
    setState(() {
      _teamId = teamId;
      _teamName = teamName;
      _search.clear();
      _colour.text = badge?.fill ?? '';
      _label.text = badge?.label ?? '';
      _error = null;
    });
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? teamId = _teamId;
    final String fill = _colour.text.trim().toUpperCase();
    final String words = _label.text.trim();
    final String? problem = teamId == null
        ? l10n.publisherBadgePickTeam
        : !isPublisherColour(fill)
        ? l10n.publisherBadgeColourInvalid
        : words.length > 24
        ? l10n.publisherBadgeLabelInvalid
        : null;
    if (problem != null || teamId == null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<PublisherBadgeDto> result = await ref
        .read(adminApiProvider)
        .setPublisherBadge(
          teamId: teamId,
          fill: fill,
          label: words.isEmpty ? null : words,
        );
    if (!mounted) return;
    switch (result) {
      case Ok<PublisherBadgeDto>():
        final String name = _teamName;
        setState(() {
          _busy = false;
          _teamId = null;
          _teamName = '';
          _colour.clear();
          _label.clear();
        });
        publisherSnack(context, l10n.publisherBadgeSaved(name));
        ref.invalidate(adminPublisherOverviewProvider);
      case Err<PublisherBadgeDto>(:final error):
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.publisherBadgesHint,
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _editor(context),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.publisherBadgesSet,
          style: context.text.titleSmall?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (widget.overview.badges.isEmpty)
          AdminEmptyState(
            icon: Icons.palette_outlined,
            title: l10n.publisherBadgesEmpty,
          ),
        for (final PublisherBadgeDto badge
            in widget.overview.badges) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _badgeRow(context, badge),
        ],
      ],
    );
  }

  Widget _editor(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final String? teamId = _teamId;
    final String? error = _error;
    final String words = _label.text.trim().isEmpty
        ? publisherShortLabel(_teamName)
        : _label.text.trim();
    return AdminCard(
      key: const Key('admin.publisher.badge.editor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (teamId == null) ...<Widget>[
            Text(
              l10n.publisherBadgeTeam,
              style: context.text.labelLarge?.copyWith(
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              key: const Key('admin.publisher.badge.search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.publisherBadgeSearch,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            ..._suggestions(context),
          ] else ...<Widget>[
            Row(
              children: <Widget>[
                PublisherBadgeDisc(
                  key: const Key('admin.publisher.badge.preview'),
                  fill: _colour.text.trim(),
                  label: words,
                  size: 72,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _teamName,
                    key: const Key('admin.publisher.badge.team'),
                    style: context.text.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('admin.publisher.badge.clear'),
                  tooltip: l10n.publisherCancel,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _teamId = null;
                          _teamName = '';
                          _error = null;
                        }),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('admin.publisher.badge.colour'),
              controller: _colour,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.publisherBadgeColour,
                hintText: '#1978D1',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (int i = 0; i < _swatches.length; i++)
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: Key('admin.publisher.badge.swatch.$i'),
                      customBorder: const CircleBorder(),
                      onTap: _busy
                          ? null
                          : () => setState(() => _colour.text = _swatches[i]),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: publisherColourOf(_swatches[i]),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                _colour.text.trim().toUpperCase() ==
                                    _swatches[i]
                                ? tokens.primary
                                : tokens.border,
                            width:
                                _colour.text.trim().toUpperCase() ==
                                    _swatches[i]
                                ? 3
                                : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('admin.publisher.badge.label'),
              controller: _label,
              enabled: !_busy,
              maxLength: 24,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.publisherBadgeLabel,
                hintText: publisherShortLabel(_teamName),
              ),
            ),
          ],
          if (error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AdminErrorBanner(message: error),
          ],
          const SizedBox(height: AppSpacing.md),
          AdminPrimaryButton(
            key: const Key('admin.publisher.badge.save'),
            label: l10n.publisherBadgeSave,
            icon: Icons.palette_rounded,
            loading: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }

  /// The clubs whose name holds what was typed; before anything is typed,
  /// the clubs of the covered matches that have no colour yet.
  List<Widget> _suggestions(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final AsyncValue<List<TeamDto>> catalog = ref.watch(teamCatalogProvider);
    final List<TeamDto>? teams = catalog.value;
    if (teams == null) {
      return <Widget>[
        const SizedBox(height: AppSpacing.sm),
        if (catalog.hasError)
          Text(
            ErrorPresenter.messageOf(catalog.error),
            style: context.text.bodySmall?.copyWith(color: tokens.errorText),
          )
        else
          const Center(child: CircularProgressIndicator()),
      ];
    }
    final String query = _search.text.trim().toLowerCase();
    final List<TeamDto> found;
    if (query.isEmpty) {
      final Set<String> names = <String>{
        for (final PublisherCandidateDto match in widget.overview.candidates)
          if (match.covered) ...<String>[match.homeName, match.awayName],
      };
      found = <TeamDto>[
        for (final TeamDto team in teams)
          if (names.contains(team.name) && _badgeOf(team.id) == null) team,
      ];
    } else {
      found = <TeamDto>[
        for (final TeamDto team in teams)
          if (team.name.toLowerCase().contains(query)) team,
      ].take(8).toList();
    }
    if (found.isEmpty) {
      return <Widget>[
        if (query.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.publisherBadgeNoTeam,
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ],
      ];
    }
    return <Widget>[
      const SizedBox(height: AppSpacing.sm),
      if (query.isEmpty)
        Text(
          l10n.publisherBadgeSuggested,
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      for (final TeamDto team in found)
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            key: Key('admin.publisher.badge.pick.${team.id}'),
            contentPadding: EdgeInsets.zero,
            leading: PublisherBadgeDisc(
              fill: _badgeOf(team.id)?.fill ?? '',
              label: _badgeOf(team.id)?.label ?? publisherShortLabel(team.name),
              size: 36,
            ),
            title: Text(
              team.name,
              style: context.text.bodyMedium?.copyWith(
                color: tokens.textPrimary,
              ),
            ),
            onTap: () => _pick(team.id, team.name),
          ),
        ),
    ];
  }

  Widget _badgeRow(BuildContext context, PublisherBadgeDto badge) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final String label = badge.label ?? publisherShortLabel(badge.teamName);
    return AdminCard(
      key: Key('admin.publisher.badge.${badge.teamId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          PublisherBadgeDisc(fill: badge.fill, label: label, size: 44),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  badge.teamName.isEmpty ? label : badge.teamName,
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${badge.fill} · $label',
                  textDirection: TextDirection.ltr,
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('admin.publisher.badge.edit.${badge.teamId}'),
            onPressed: _busy ? null : () => _pick(badge.teamId, badge.teamName),
            child: Text(l10n.publisherBadgeEdit),
          ),
        ],
      ),
    );
  }
}

/// [kind]'s label (`goal`, `final`, `correction`).
String publisherKindLabel(String kind, AppLocalizations l10n) => switch (kind) {
  'goal' => l10n.publisherKindGoal,
  'final' => l10n.publisherKindFinal,
  'correction' => l10n.publisherKindCorrection,
  _ => kind,
};

/// [state]'s label.
String publisherStateLabel(String state, AppLocalizations l10n) =>
    switch (state) {
      'queued' => l10n.publisherStateQueued,
      'published' => l10n.publisherStatePublished,
      'dry_run' => l10n.publisherStateDryRun,
      'ready_to_share' => l10n.publisherStateReadyToShare,
      'shared' => l10n.publisherStateShared,
      'failed' => l10n.publisherStateFailed,
      'uncertain' => l10n.publisherStateUncertain,
      'skipped' => l10n.publisherStateSkipped,
      'cancelled' => l10n.publisherStateCancelled,
      _ => state,
    };

Color _stateColour(String state, AppTokens tokens) => switch (state) {
  'published' || 'shared' => tokens.successText,
  'failed' => tokens.errorText,
  'uncertain' => tokens.errorText,
  'ready_to_share' => tokens.primaryText,
  'skipped' || 'cancelled' => tokens.textMuted,
  _ => tokens.textSecondary,
};

/// A small rounded label.
class _Tag extends StatelessWidget {
  const _Tag({super.key, required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour),
      ),
      child: Text(
        text,
        style: context.text.labelMedium?.copyWith(
          color: colour,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// «السجل»: the latest posts, each with its state, its error, a preview of
/// its picture, and what the admin may do to it.
class PublisherLogTab extends ConsumerStatefulWidget {
  /// Creates the tab.
  const PublisherLogTab({super.key, required this.overview});

  /// The panel as last read.
  final PublisherOverviewDto overview;

  @override
  ConsumerState<PublisherLogTab> createState() => _PublisherLogTabState();
}

class _PublisherLogTabState extends ConsumerState<PublisherLogTab> {
  /// `all`, `attention` or a platform.
  String _filter = 'all';

  final Set<String> _busy = <String>{};

  /// X posts whose share sheet was opened here: «تمت المشاركة» stands out.
  final Set<String> _opened = <String>{};

  bool _shows(PublisherPostDto post) => switch (_filter) {
    'all' => true,
    'attention' => publisherAttentionStates.contains(post.state),
    _ => post.platform == _filter,
  };

  Future<void> _act(PublisherPostDto post, String action) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String platform = publisherPlatformLabel(post.platform, l10n);
    if (action == 'retry' && post.state == 'uncertain') {
      final bool sure = await publisherConfirm(
        context,
        title: l10n.publisherUncertainTitle,
        body: l10n.publisherUncertainBody(platform),
        action: l10n.publisherUncertainConfirm,
      );
      if (!sure || !mounted) return;
    }
    if (action == 'cancel') {
      final bool sure = await publisherConfirm(
        context,
        title: l10n.publisherCancelTitle,
        body: l10n.publisherCancelBody,
        action: l10n.publisherCancelConfirm,
      );
      if (!sure || !mounted) return;
    }
    setState(() => _busy.add(post.id));
    final Result<String> result = await ref
        .read(adminApiProvider)
        .actOnPublisherPost(post.id, action);
    if (!mounted) return;
    setState(() => _busy.remove(post.id));
    switch (result) {
      case Ok<String>():
        publisherSnack(context, switch (action) {
          'retry' => l10n.publisherRetried,
          'cancel' => l10n.publisherCancelled,
          _ => l10n.publisherMarkedShared,
        });
        ref.invalidate(adminPublisherOverviewProvider);
      case Err<String>(:final error):
        publisherSnack(context, ErrorPresenter.message(error));
    }
  }

  /// Opens the phone's share sheet with the post's words and picture, for
  /// the admin to pick X.
  Future<void> _share(PublisherPostDto post) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ShareSheet share = ref.read(publisherShareSheetProvider);
    setState(() => _busy.add(post.id));
    Uint8List? bytes;
    if (post.hasCard) {
      final Result<Uint8List?> card = await ref
          .read(adminApiProvider)
          .publisherCard(post.id);
      if (!mounted) return;
      switch (card) {
        case Ok<Uint8List?>(:final value):
          bytes = value;
        case Err<Uint8List?>(:final error):
          setState(() => _busy.remove(post.id));
          publisherSnack(context, ErrorPresenter.message(error));
          return;
      }
    }
    final String name =
        'nukhba_${post.id.length > 8 ? post.id.substring(0, 8) : post.id}.jpg';
    bool opened = true;
    try {
      await share(
        ShareParams(
          text: post.body,
          files: bytes == null
              ? null
              : <XFile>[
                  XFile.fromData(bytes, mimeType: 'image/jpeg', name: name),
                ],
          fileNameOverrides: bytes == null ? null : <String>[name],
        ),
      );
    } on Object catch (error) {
      debugPrint('publisher share: $error');
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(post.id);
      if (opened) _opened.add(post.id);
    });
    if (!opened) publisherSnack(context, l10n.publisherShareFailed);
  }

  void _copy(PublisherPostDto post) {
    unawaited(Clipboard.setData(ClipboardData(text: post.body)));
    publisherSnack(context, AppLocalizations.of(context).publisherCopied);
  }

  Future<void> _preview(PublisherPostDto post) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppLocalizations l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          key: const Key('admin.publisher.preview'),
          contentPadding: const EdgeInsets.all(AppSpacing.md),
          content: SizedBox(
            width: 320,
            child: AspectRatio(
              aspectRatio: 1080 / 1350,
              child: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  final AsyncValue<Uint8List?> card = ref.watch(
                    adminPublisherCardProvider(post.id),
                  );
                  return card.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object error, _) => Center(
                      child: Text(
                        ErrorPresenter.messageOf(error),
                        key: const Key('admin.publisher.preview.error'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    data: (Uint8List? bytes) => bytes == null
                        ? Center(child: Text(l10n.publisherCardMissing))
                        : Image.memory(
                            bytes,
                            key: const Key('admin.publisher.preview.image'),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                Center(child: Text(l10n.publisherCardMissing)),
                          ),
                  );
                },
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('admin.publisher.preview.close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.publisherClose),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<PublisherPostDto> posts = widget.overview.posts
        .where(_shows)
        .toList();
    final List<(String, String)> filters = <(String, String)>[
      ('all', l10n.publisherFilterAll),
      ('attention', l10n.publisherFilterAttention),
      for (final String platform in publisherPlatforms)
        (platform, publisherPlatformLabel(platform, l10n)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final (String value, String label) in filters)
              ChoiceChip(
                key: Key('admin.publisher.log.filter.$value'),
                label: Text(label),
                selected: _filter == value,
                onSelected: (_) => setState(() => _filter = value),
              ),
          ],
        ),
        if (posts.isEmpty)
          AdminEmptyState(
            icon: Icons.receipt_long_rounded,
            title: l10n.publisherLogEmpty,
          ),
        for (final PublisherPostDto post in posts) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _postCard(context, post),
        ],
      ],
    );
  }

  Widget _postCard(BuildContext context, PublisherPostDto post) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final bool busy = _busy.contains(post.id);
    final String? error = post.error;
    final String? publishedAt = post.publishedAt;
    final bool ready = post.state == 'ready_to_share';
    return AdminCard(
      key: Key('admin.publisher.post.${post.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _Tag(
                text: publisherPlatformLabel(post.platform, l10n),
                colour: tokens.textSecondary,
              ),
              _Tag(
                text: publisherKindLabel(post.kind, l10n),
                colour: tokens.textSecondary,
              ),
              _Tag(
                key: Key('admin.publisher.post.${post.id}.state'),
                text: publisherStateLabel(post.state, l10n),
                colour: _stateColour(post.state, tokens),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            post.matchLabel,
            style: context.text.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            post.body,
            style: context.text.bodyMedium?.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            <String>[
              l10n.publisherCreatedAt(formatTimestamp(context, post.createdAt)),
              if (publishedAt != null)
                l10n.publisherPublishedAt(
                  formatTimestamp(context, publishedAt),
                ),
              if (post.attempts > 0) l10n.publisherAttempts(post.attempts),
            ].join(' · '),
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          if (error != null && error.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.publisherError(error),
              key: Key('admin.publisher.post.${post.id}.error'),
              style: context.text.bodySmall?.copyWith(color: tokens.errorText),
            ),
          ],
          if (post.state == 'uncertain') ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Container(
              key: Key('admin.publisher.post.${post.id}.uncertain'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: tokens.goldContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: tokens.textPrimary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.publisherUncertainNote,
                      style: context.text.bodySmall?.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              if (post.hasCard)
                TextButton.icon(
                  key: Key('admin.publisher.post.${post.id}.preview'),
                  onPressed: () => _preview(post),
                  icon: const Icon(Icons.image_rounded),
                  label: Text(l10n.publisherPreview),
                ),
              TextButton.icon(
                key: Key('admin.publisher.post.${post.id}.copy'),
                onPressed: () => _copy(post),
                icon: const Icon(Icons.copy_rounded),
                label: Text(l10n.publisherCopyText),
              ),
              if (ready)
                FilledButton.icon(
                  key: Key('admin.publisher.post.${post.id}.share'),
                  onPressed: busy ? null : () => _share(post),
                  icon: const Icon(Icons.share_rounded),
                  label: Text(l10n.publisherShareX),
                ),
              if (ready)
                (_opened.contains(post.id)
                    ? FilledButton.icon(
                        key: Key('admin.publisher.post.${post.id}.shared'),
                        onPressed: busy ? null : () => _act(post, 'shared'),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l10n.publisherMarkShared),
                      )
                    : OutlinedButton.icon(
                        key: Key('admin.publisher.post.${post.id}.shared'),
                        onPressed: busy ? null : () => _act(post, 'shared'),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l10n.publisherMarkShared),
                      )),
              if (publisherRetryStates.contains(post.state))
                OutlinedButton.icon(
                  key: Key('admin.publisher.post.${post.id}.retry'),
                  onPressed: busy ? null : () => _act(post, 'retry'),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(l10n.publisherRetryPost),
                ),
              if (publisherCancelStates.contains(post.state))
                TextButton.icon(
                  key: Key('admin.publisher.post.${post.id}.cancel'),
                  onPressed: busy ? null : () => _act(post, 'cancel'),
                  icon: const Icon(Icons.block_rounded),
                  label: Text(l10n.publisherCancelPost),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «الأداء»: what the published posts earned, read once a day after each
/// went out (reach, reactions, comments, shares), per platform and the
/// posts that earned most.
class PublisherPerformanceTab extends StatelessWidget {
  /// Creates the tab.
  const PublisherPerformanceTab({super.key, required this.overview});

  /// The panel as last read.
  final PublisherOverviewDto overview;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final List<PublisherPostDto> published = <PublisherPostDto>[
      for (final PublisherPostDto post in overview.posts)
        if (post.state == 'published') post,
    ];
    final int sharedOnX = overview.posts
        .where((PublisherPostDto p) => p.platform == 'x' && p.state == 'shared')
        .length;
    final List<PublisherPostDto> top =
        <PublisherPostDto>[
          for (final PublisherPostDto post in published)
            if (publisherEngagement(post) != null) post,
        ]..sort(
          (PublisherPostDto a, PublisherPostDto b) =>
              publisherEngagement(b)!.compareTo(publisherEngagement(a)!),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.publisherPerformanceHint,
          style: context.text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        for (final String platform in <String>[
          'facebook',
          'instagram',
        ]) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _platformCard(context, platform, <PublisherPostDto>[
            for (final PublisherPostDto post in published)
              if (post.platform == platform) post,
          ]),
        ],
        const SizedBox(height: AppSpacing.sm),
        AdminCard(
          key: const Key('admin.publisher.performance.x'),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.publisherPlatformX,
                style: context.text.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                l10n.publisherSharedCount(sharedOnX),
                style: context.text.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.publisherTopPosts,
          style: context.text.titleSmall?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (top.isEmpty)
          AdminEmptyState(
            icon: Icons.insights_rounded,
            title: l10n.publisherPerformanceEmpty,
          ),
        for (final PublisherPostDto post in top.take(10)) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AdminCard(
            key: Key('admin.publisher.top.${post.id}'),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '${post.matchLabel} · '
                  '${publisherKindLabel(post.kind, l10n)} · '
                  '${publisherPlatformLabel(post.platform, l10n)}',
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _metrics(context, <int?>[
                  post.reach,
                  post.reactions,
                  post.comments,
                  post.shares,
                ]),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _platformCard(
    BuildContext context,
    String platform,
    List<PublisherPostDto> posts,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final List<PublisherPostDto> read = <PublisherPostDto>[
      for (final PublisherPostDto post in posts)
        if (publisherEngagement(post) != null || post.reach != null) post,
    ];
    int? sum(int? Function(PublisherPostDto) field) {
      int? total;
      for (final PublisherPostDto post in read) {
        final int? value = field(post);
        if (value != null) total = (total ?? 0) + value;
      }
      return total;
    }

    final int waiting = posts.length - read.length;
    return AdminCard(
      key: Key('admin.publisher.performance.$platform'),
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
            l10n.publisherPublishedCount(posts.length),
            style: context.text.bodyMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _metrics(context, <int?>[
            sum((PublisherPostDto p) => p.reach),
            sum((PublisherPostDto p) => p.reactions),
            sum((PublisherPostDto p) => p.comments),
            sum((PublisherPostDto p) => p.shares),
          ]),
          if (waiting > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.publisherMetricsWaiting(waiting),
              style: context.text.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Reach, reactions, comments and shares; a dash for a number not read.
  Widget _metrics(BuildContext context, List<int?> values) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final List<String> labels = <String>[
      l10n.publisherReach,
      l10n.publisherReactions,
      l10n.publisherComments,
      l10n.publisherShares,
    ];
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (int i = 0; i < labels.length; i++)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                values[i] == null ? '—' : '${values[i]}',
                style: context.text.titleMedium?.copyWith(
                  color: tokens.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                labels[i],
                style: context.text.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
