/// لوحة المشرف لتتويج بطل الشهر (migration 0077): يختار المشرف الشهر،
/// فيرى الترتيب النهائي كما حسبه الخادم، ويحدّد البطل أو البطلين من أصحاب
/// المركز الأول، ويضيف صورة البطل، ويعاين الاحتفال كما سيظهر في شاشة
/// المتصدرين، ثم يتوّج. الخادم وحده يقرر من يحق له التتويج.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared/shared.dart';

import '../../../../core/design/app_radius.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/error/error_presenter.dart';
import '../../../../core/providers.dart';
import '../../../../core/ui/app_dialog.dart';
import '../../../../core/ui/user_avatar.dart';
import '../../../competition/month_label.dart';
import '../../../leaderboards/champions_providers.dart';
import '../../../leaderboards/widgets/champion_spotlight.dart';
import '../../widgets/admin_pickers.dart';
import '../../widgets/admin_ui_kit.dart';

/// `GET /admin/champions/{seasonId}` -- the crowning preview of a month.
final adminChampionCandidatesProvider = FutureProvider.autoDispose
    .family<ChampionCandidatesDto, String>((ref, seasonId) async {
      return switch (await ref
          .watch(adminApiProvider)
          .championCandidates(seasonId)) {
        Ok<ChampionCandidatesDto>(:final value) => value,
        Err<ChampionCandidatesDto>(:final error) => throw error,
      };
    });

/// A picture the admin picked, with its type read from its own bytes.
typedef ChampionPhoto = ({Uint8List bytes, String mime});

/// Opens the gallery and answers the picked picture, or null when the admin
/// backed out.
typedef ChampionPhotoPicker = Future<ChampionPhoto?> Function();

/// The server's cap for a picture (`User.validateAvatar`).
const int championPhotoMaxBytes = 512 * 1024;

/// The picture's type from its first bytes (PNG, JPEG or WEBP), or null for
/// anything else. The picker keeps a PNG a PNG, so a cut-out picture keeps
/// its transparency.
String? championPhotoMime(List<int> b) {
  if (b.length >= 4 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

Future<ChampionPhoto?> _pickFromGallery() async {
  final XFile? picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 640,
    maxHeight: 640,
    imageQuality: 85,
  );
  if (picked == null) return null;
  final Uint8List bytes = await picked.readAsBytes();
  return (bytes: bytes, mime: championPhotoMime(bytes) ?? 'image/jpeg');
}

/// The champion section of the admin hub.
class ChampionAdminSection extends ConsumerStatefulWidget {
  /// Creates the section; [pickPhoto] replaces the gallery (tests).
  const ChampionAdminSection({this.pickPhoto, super.key});

  /// Opens the gallery; null uses the device's picker.
  final ChampionPhotoPicker? pickPhoto;

  @override
  ConsumerState<ChampionAdminSection> createState() =>
      _ChampionAdminSectionState();
}

class _ChampionAdminSectionState extends ConsumerState<ChampionAdminSection> {
  SeasonDto? _month;
  final Set<String> _chosen = <String>{};
  final Map<String, ChampionPhoto> _photos = <String, ChampionPhoto>{};
  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Picks a picture, checks it, and answers it; null (with a message) when
  /// it cannot be used.
  Future<ChampionPhoto?> _pick() async {
    final ChampionPhoto? photo;
    try {
      photo = await (widget.pickPhoto ?? _pickFromGallery)();
    } on Object {
      if (mounted) _snack('تعذّر فتح الصورة');
      return null;
    }
    if (photo == null || !mounted) return null;
    if (photo.bytes.length > championPhotoMaxBytes) {
      _snack('الصورة أكبر من 512 ك.ب، اختر صورة أصغر');
      return null;
    }
    return photo;
  }

  Future<void> _pickFor(String userId) async {
    final ChampionPhoto? photo = await _pick();
    if (photo == null || !mounted) return;
    setState(() => _photos[userId] = photo);
  }

  Future<bool> _upload(String seasonId, String userId, ChampionPhoto p) async {
    final Result<MonthChampionsDto> result = await ref
        .read(adminApiProvider)
        .setChampionPhoto(
          seasonId: seasonId,
          userId: userId,
          bytes: p.bytes,
          contentType: p.mime,
        );
    return result is Ok<MonthChampionsDto>;
  }

  /// Replaces the picture of a champion already crowned.
  Future<void> _replacePhoto(String seasonId, String userId) async {
    final ChampionPhoto? photo = await _pick();
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    final bool ok = await _upload(seasonId, userId, photo);
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(monthChampionsProvider);
    _snack(ok ? 'تم حفظ صورة البطل' : 'تعذّر رفع الصورة، أعد المحاولة');
  }

  Future<void> _crown(ChampionCandidatesDto month) async {
    final List<ChampionCandidateDto> chosen = <ChampionCandidateDto>[
      for (final ChampionCandidateDto c in month.candidates)
        if (_chosen.contains(c.userId)) c,
    ];
    if (chosen.isEmpty) return;
    final String names = chosen.map((c) => c.displayName).join(' و');
    final bool force = month.unscoredFixtures > 0;
    final bool? confirmed = await AppDialog.confirm(
      context,
      title: 'تتويج ${monthLabelFromStored(month.seasonLabel)}',
      message:
          'سيُتوَّج: $names.\n'
          'يظهر الاحتفال في شاشة المتصدرين 48 ساعة، ويبقى البطل في سجل '
          'الأبطال. التتويج لا يُلغى.'
          '${force ? '\nتنبيه: ${month.unscoredFixtures} مباراة بلا نتيجة بعد.' : ''}',
      confirmLabel: 'تتويج',
      cancelLabel: 'إلغاء',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final Result<MonthChampionsDto> crowned = await ref
        .read(adminApiProvider)
        .crownChampions(
          seasonId: month.seasonId,
          userIds: <String>[
            for (final ChampionCandidateDto c in chosen) c.userId,
          ],
          force: force,
        );
    if (!mounted) return;
    if (crowned is Err<MonthChampionsDto>) {
      setState(() => _busy = false);
      _snack(ErrorPresenter.message(crowned.error));
      ref.invalidate(adminChampionCandidatesProvider(month.seasonId));
      return;
    }

    // The crowning stands whatever happens to a picture; one that did not
    // go up is added again from the crowned month's card.
    bool photosOk = true;
    for (final ChampionCandidateDto c in chosen) {
      final ChampionPhoto? photo = _photos[c.userId];
      if (photo == null) continue;
      if (!await _upload(month.seasonId, c.userId, photo)) photosOk = false;
      if (!mounted) return;
    }
    setState(() {
      _busy = false;
      _chosen.clear();
      _photos.clear();
    });
    ref.invalidate(monthChampionsProvider);
    ref.invalidate(adminChampionCandidatesProvider(month.seasonId));
    _snack(
      photosOk
          ? 'تم التتويج، والاحتفال ظاهر الآن في شاشة المتصدرين'
          : 'تم التتويج، وتعذّر رفع الصورة: أضفها من «تغيير الصورة»',
    );
  }

  @override
  Widget build(BuildContext context) {
    final SeasonDto? month = _month;
    return ListView(
      key: const Key('admin.champions.list'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        const AdminSectionHeader(
          title: 'تتويج بطل الشهر',
          subtitle:
              'اختر الشهر، راجع ترتيبه النهائي، حدّد البطل وأضف صورته، '
              'وعاين الاحتفال كما يراه اللاعبون قبل التتويج.',
        ),
        AdminCard(
          child: MonthPickerField(
            enabled: !_busy,
            selectedId: month?.id,
            onSelected: (SeasonDto m) => setState(() {
              _month = m;
              _chosen.clear();
              _photos.clear();
            }),
          ),
        ),
        if (month != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          ref
              .watch(adminChampionCandidatesProvider(month.id))
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, _) => Column(
                  children: <Widget>[
                    AdminErrorBanner(
                      key: const Key('admin.champions.error'),
                      message: error is AppError
                          ? ErrorPresenter.message(error)
                          : 'تعذّر تحميل ترتيب الشهر',
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(
                        adminChampionCandidatesProvider(month.id),
                      ),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
                data: (ChampionCandidatesDto data) => data.crowned.isEmpty
                    ? _toCrown(context, data)
                    : _crowned(context, data),
              ),
        ],
      ],
    );
  }

  /// A month not crowned yet: its state, the top of its final board, the
  /// chosen champions' pictures, the preview and the crowning button.
  Widget _toCrown(BuildContext context, ChampionCandidatesDto data) {
    final AppTokens t = context.tokens;
    final List<MonthChampionDto> preview = <MonthChampionDto>[
      for (final ChampionCandidateDto c in data.candidates)
        if (_chosen.contains(c.userId))
          MonthChampionDto(
            seasonId: data.seasonId,
            seasonLabel: data.seasonLabel,
            userId: c.userId,
            displayName: c.displayName,
            points: c.points,
            exactCount: c.exactCount,
            decidedCount: c.decidedCount,
            referralPoints: c.referralPoints,
            crownedAt: '',
            celebrateUntil: '',
            avatarUrl: c.avatarUrl,
          ),
    ];
    final bool canCrown = data.ended && _chosen.isNotEmpty && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!data.ended)
          const AdminErrorBanner(
            key: Key('admin.champions.notOver'),
            message: 'الشهر لم ينتهِ بعد، ولا يُتوَّج قبل انتهائه.',
          ),
        if (data.unscoredFixtures > 0) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AdminErrorBanner(
            key: const Key('admin.champions.unscored'),
            message:
                '${data.unscoredFixtures} مباراة بلا نتيجة بعد. '
                'التتويج الآن يعتمد الترتيب الحالي.',
          ),
        ],
        if (data.candidates.isEmpty)
          const AdminEmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'لا ترتيب لهذا الشهر بعد',
          ),
        if (data.candidates.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            'الترتيب النهائي: يُتوَّج صاحب المركز الأول، أو اثنان متعادلان.',
            style: context.text.bodySmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AdminCard(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: <Widget>[
                  for (final ChampionCandidateDto c in data.candidates)
                    _CandidateRow(
                      candidate: c,
                      chosen: _chosen.contains(c.userId),
                      canChoose:
                          c.rank == 1 &&
                          !_busy &&
                          (_chosen.contains(c.userId) || _chosen.length < 2),
                      hasPhoto: _photos.containsKey(c.userId),
                      onChosen: (bool on) => setState(() {
                        if (on) {
                          _chosen.add(c.userId);
                        } else {
                          _chosen.remove(c.userId);
                          _photos.remove(c.userId);
                        }
                      }),
                      onPhoto: _busy
                          ? null
                          : () => unawaited(_pickFor(c.userId)),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (preview.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'المعاينة: هكذا يظهر أعلى شاشة المتصدرين 48 ساعة',
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Preview(
            champions: preview,
            photos: <String, Uint8List>{
              for (final MapEntry<String, ChampionPhoto> e in _photos.entries)
                e.key: e.value.bytes,
            },
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        AdminPrimaryButton(
          key: const Key('admin.champions.crown'),
          label: 'تتويج البطل',
          icon: Icons.emoji_events_rounded,
          loading: _busy,
          onPressed: canCrown ? () => unawaited(_crown(data)) : null,
        ),
      ],
    );
  }

  /// A crowned month: its champions, a picture to change, and the same
  /// preview the players see.
  Widget _crowned(BuildContext context, ChampionCandidatesDto data) {
    final List<MonthChampionDto> champions = <MonthChampionDto>[
      for (final MonthChampionDto c
          in ref.watch(monthChampionsProvider).value?.champions ??
              const <MonthChampionDto>[])
        if (c.seasonId == data.seasonId) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AdminSuccessBanner(
          key: Key('admin.champions.crownedBanner'),
          message: 'هذا الشهر متوَّج.',
        ),
        const SizedBox(height: AppSpacing.md),
        for (final MonthChampionDto c in champions) ...<Widget>[
          AdminListRow(
            key: Key('admin.champions.crowned.${c.userId}'),
            leadingIcon: Icons.emoji_events_rounded,
            leadingColor: context.tokens.gold,
            title: c.displayName,
            trailing: AdminSecondaryButton(
              key: Key('admin.champions.replacePhoto.${c.userId}'),
              label: c.photoUrl == null ? 'إضافة صورة البطل' : 'تغيير الصورة',
              icon: Icons.add_photo_alternate_outlined,
              onPressed: _busy
                  ? null
                  : () => unawaited(_replacePhoto(c.seasonId, c.userId)),
            ),
          ),
        ],
        if (champions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _Preview(champions: champions),
        ],
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.chosen,
    required this.canChoose,
    required this.hasPhoto,
    required this.onChosen,
    required this.onPhoto,
  });

  final ChampionCandidateDto candidate;
  final bool chosen;
  final bool canChoose;
  final bool hasPhoto;
  final ValueChanged<bool> onChosen;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ChampionCandidateDto c = candidate;
    final String accuracy = c.decidedCount <= 0
        ? '—'
        : '${(c.exactCount * 100 / c.decidedCount).round()}%';
    return Padding(
      key: Key('admin.champions.candidate.${c.userId}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      // The picture button sits on its own line: beside the name it
      // squeezed the row past a phone's width.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(
                key: Key('admin.champions.choose.${c.userId}'),
                value: chosen,
                onChanged: canChoose ? (bool? v) => onChosen(v ?? false) : null,
              ),
              Text(
                '${c.rank}',
                style: context.text.labelLarge?.copyWith(
                  color: c.rank == 1 ? t.gold : t.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              UserAvatar(
                displayName: c.displayName,
                avatarUrl: c.avatarUrl,
                size: 32,
                gradient: false,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      c.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${c.points} نقطة · دقة $accuracy · دعوات ${c.referralPoints}',
                      style: context.text.labelSmall?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (chosen)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: Key('admin.champions.photo.${c.userId}'),
                onPressed: onPhoto,
                icon: Icon(
                  hasPhoto
                      ? Icons.check_circle_rounded
                      : Icons.add_photo_alternate_outlined,
                  color: hasPhoto ? t.success : null,
                ),
                label: Text(hasPhoto ? 'تغيير الصورة' : 'إضافة صورة البطل'),
              ),
            ),
        ],
      ),
    );
  }
}

/// The top of the leaderboard as the players will see it: the faint
/// picture behind, then the spotlight.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.champions,
    this.photos = const <String, Uint8List>{},
  });

  final List<MonthChampionDto> champions;
  final Map<String, Uint8List> photos;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      key: const Key('admin.champions.preview'),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ChampionBackdrop(
              champions: champions,
              previewPhotos: photos,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: ChampionSpotlight(
              champions: champions,
              keyPrefix: 'admin.champions.spotlight',
              previewPhotos: photos,
            ),
          ),
        ],
      ),
    );
  }
}
