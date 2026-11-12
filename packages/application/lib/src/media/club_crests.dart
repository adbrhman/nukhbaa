import 'package:application/src/identity/authorization.dart';
import 'package:application/src/media/ports/crest_catalog.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What the app may show (`GET /crests`, script 265): the URL of every
/// active club crest by slug, or none while club crests are off.
final class CrestManifest {
  /// Creates the manifest.
  const CrestManifest({
    required this.version,
    required this.clubsEnabled,
    required this.crests,
  });

  /// Changes whenever the list changes: the app keeps its copy while it is
  /// the same.
  final String version;

  /// Whether club crests show at all.
  final bool clubsEnabled;

  /// The URL of each crest the app may show, by slug.
  final Map<String, String> crests;
}

/// Query use-case: the club crests the app may show (script 265, decided by
/// the owner on 2026-11-11). Read on every start of the app, which keeps
/// the files it downloads and drops any that left the list: a crest the
/// owner hides is gone from the phones at their next start.
///
/// Any signed-in user. [baseUrl] is the bucket's public address
/// (`https://<ref>.supabase.co/storage/v1/object/public/crests/`); without
/// it the list is empty and the app draws its discs. Never throws.
final class GetCrestManifest {
  /// Creates the use-case over its collaborators.
  const GetCrestManifest({required CrestCatalog catalog, String? baseUrl})
    : _catalog = catalog,
      _baseUrl = baseUrl;

  final CrestCatalog _catalog;
  final String? _baseUrl;

  /// The manifest, for [principal].
  Future<Result<CrestManifest>> call({
    required AuthenticatedUser principal,
  }) async {
    final Result<AuthenticatedUser> auth = Authorization.requireRole(
      principal,
      PlatformRole.user,
    );
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final Result<CrestList> read = await _catalog.crests();
    if (read is Err<CrestList>) return Result.err(read.error);
    final CrestList list = (read as Ok<CrestList>).value;
    final String base = (_baseUrl ?? '').trim();
    final Map<String, String> crests = <String, String>{
      if (list.clubsEnabled && base.isNotEmpty)
        for (final ClubCrest crest in list.crests)
          if (crest.status == CrestStatus.active)
            crest.slug: '$base${crest.objectPath}',
    };
    final List<String> keys = crests.keys.toList()..sort();
    return Result.ok(
      CrestManifest(
        version: _fnv1a(
          <String>[
            if (list.clubsEnabled) 'on' else 'off',
            for (final String slug in keys) '$slug=${crests[slug]}',
          ].join('\n'),
        ),
        clubsEnabled: list.clubsEnabled,
        crests: crests,
      ),
    );
  }

  /// FNV-1a over [text]'s code units, as 8 hex digits: the same on every
  /// server, every run.
  static String _fnv1a(String text) {
    int hash = 0x811c9dc5;
    for (final int unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// The owner's view: every crest, the switch and the latest changes.
final class CrestState {
  /// Creates the view.
  const CrestState({required this.list, required this.events, this.baseUrl});

  /// Every crest and the switch.
  final CrestList list;

  /// The latest changes, newest first.
  final List<CrestEvent> events;

  /// The bucket's public address, or null when the server has none.
  final String? baseUrl;

  /// The URL of [crest]'s file, or null once deleted or without [baseUrl].
  String? urlOf(ClubCrest crest) {
    final String base = (baseUrl ?? '').trim();
    if (base.isEmpty || crest.status == CrestStatus.deleted) return null;
    return '$base${crest.objectPath}';
  }
}

/// The club crests, managed by the owner admin alone (script 265, decided
/// by the owner on 2026-11-11): hide one at once (a complaint), show it
/// again, delete it for good (its file erased, after its name is typed), or
/// turn every club crest off. Every change keeps its reason, and the
/// complainant when there is one. A hidden or deleted crest leaves the
/// phones at their next start.
///
/// Only the owner admin ([OwnerNotices.ownerId]); any other admin is refused
/// (`admin.owner_only`), a player by the role gate. Never throws.
final class OwnerCrests {
  /// Creates the use-case over its collaborators.
  const OwnerCrests({
    required CrestCatalog catalog,
    required CrestFileEraser files,
    required OwnerNotices owner,
    String? baseUrl,
  }) : _catalog = catalog,
       _files = files,
       _owner = owner,
       _baseUrl = baseUrl;

  final CrestCatalog _catalog;
  final CrestFileEraser _files;
  final OwnerNotices _owner;
  final String? _baseUrl;

  /// The longest reason or complainant kept.
  static const int maxText = 200;

  /// Every crest, the switch and the latest 50 changes.
  Future<Result<CrestState>> state({
    required AuthenticatedUser principal,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final Result<CrestList> list = await _catalog.crests();
    if (list is Err<CrestList>) return Result.err(list.error);
    final Result<List<CrestEvent>> events = await _catalog.events();
    if (events is Err<List<CrestEvent>>) return Result.err(events.error);
    return Result.ok(
      CrestState(
        list: (list as Ok<CrestList>).value,
        events: (events as Ok<List<CrestEvent>>).value,
        baseUrl: _baseUrl,
      ),
    );
  }

  /// Hides [slug] from every phone, for [reason].
  Future<Result<void>> hide({
    required AuthenticatedUser principal,
    required String slug,
    required String? reason,
    String? complainant,
  }) => _move(
    principal: principal,
    slug: slug,
    from: const <CrestStatus>{CrestStatus.active},
    to: CrestStatus.hidden,
    action: 'hidden',
    reason: reason,
    complainant: complainant,
  );

  /// Shows [slug] again.
  Future<Result<void>> show({
    required AuthenticatedUser principal,
    required String slug,
    String? reason,
  }) => _move(
    principal: principal,
    slug: slug,
    from: const <CrestStatus>{CrestStatus.hidden},
    to: CrestStatus.active,
    action: 'shown',
    reason: (reason ?? '').trim().isEmpty ? 'أُعيد إظهاره' : reason,
    complainant: null,
  );

  /// Deletes [slug] for good, its file erased: [confirm] must be [slug]
  /// itself, typed.
  Future<Result<void>> delete({
    required AuthenticatedUser principal,
    required String slug,
    required String? confirm,
    required String? reason,
    String? complainant,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    if ((confirm ?? '').trim() != slug) {
      return const Result.err(
        AppError.validation(
          'crest.confirm_mismatch',
          'اكتب اسم الشعار كما هو لتأكيد الحذف.',
        ),
      );
    }
    final String? why = _text(reason);
    if (why == null) return const Result.err(_reasonRequired);
    final Result<CrestList> list = await _catalog.crests();
    if (list is Err<CrestList>) return Result.err(list.error);
    ClubCrest? crest;
    for (final ClubCrest c in (list as Ok<CrestList>).value.crests) {
      if (c.slug == slug) crest = c;
    }
    if (crest == null) return const Result.err(_notFound);
    if (crest.status == CrestStatus.deleted) {
      return const Result.err(_wrongState);
    }
    final Result<void> erased = await _files.erase(crest.objectPath);
    if (erased is Err<void>) return Result.err(erased.error);
    return _write(
      slug: slug,
      from: const <CrestStatus>{CrestStatus.active, CrestStatus.hidden},
      to: CrestStatus.deleted,
      action: 'deleted',
      reason: why,
      complainant: _text(complainant),
      by: (gate as Ok<UserId>).value,
    );
  }

  /// Turns every club crest on or off, for [reason].
  Future<Result<void>> setClubsEnabled({
    required AuthenticatedUser principal,
    required bool enabled,
    required String? reason,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final String? why = _text(reason);
    if (why == null) return const Result.err(_reasonRequired);
    return _catalog.setClubsEnabled(
      enabled: enabled,
      reason: why,
      by: (gate as Ok<UserId>).value,
    );
  }

  Future<Result<void>> _move({
    required AuthenticatedUser principal,
    required String slug,
    required Set<CrestStatus> from,
    required CrestStatus to,
    required String action,
    required String? reason,
    required String? complainant,
  }) async {
    final Result<UserId> gate = await _ownerOnly(principal);
    if (gate is Err<UserId>) return Result.err(gate.error);
    final String? why = _text(reason);
    if (why == null) return const Result.err(_reasonRequired);
    final Result<CrestList> list = await _catalog.crests();
    if (list is Err<CrestList>) return Result.err(list.error);
    if (!(list as Ok<CrestList>).value.crests.any((c) => c.slug == slug)) {
      return const Result.err(_notFound);
    }
    return _write(
      slug: slug,
      from: from,
      to: to,
      action: action,
      reason: why,
      complainant: _text(complainant),
      by: (gate as Ok<UserId>).value,
    );
  }

  Future<Result<void>> _write({
    required String slug,
    required Set<CrestStatus> from,
    required CrestStatus to,
    required String action,
    required String reason,
    required String? complainant,
    required UserId by,
  }) async {
    final Result<bool> written = await _catalog.setStatus(
      slug: slug,
      from: from,
      to: to,
      action: action,
      reason: reason,
      complainant: complainant,
      by: by,
    );
    if (written is Err<bool>) return Result.err(written.error);
    return (written as Ok<bool>).value
        ? const Result.ok(null)
        : const Result.err(_wrongState);
  }

  /// [raw] trimmed, or null when blank or too long.
  static String? _text(String? raw) {
    final String text = (raw ?? '').trim();
    if (text.isEmpty || text.length > maxText) return null;
    return text;
  }

  static const AppError _reasonRequired = AppError.validation(
    'crest.reason_required',
    'اكتب السبب (200 حرف على الأكثر).',
  );

  static const AppError _notFound = AppError.invariant(
    'crest.not_found',
    'لا شعار بهذا الاسم.',
  );

  static const AppError _wrongState = AppError.invariant(
    'crest.state',
    'حالة الشعار لا تسمح بهذا: قد يكون مخفياً أو محذوفاً بالفعل.',
  );

  /// The owner admin's id when [principal] is he; refused otherwise.
  Future<Result<UserId>> _ownerOnly(AuthenticatedUser principal) async {
    final Result<AuthenticatedUser> role = Authorization.requireRole(
      principal,
      PlatformRole.admin,
    );
    if (role is Err<AuthenticatedUser>) return Result.err(role.error);
    final Result<UserId?> found = await _owner.ownerId();
    final UserId? owner = switch (found) {
      Ok<UserId?>(:final value) => value,
      Err<UserId?>() => null,
    };
    if (owner == null || owner != principal.userId) {
      return const Result.err(
        AppError.invariant(
          'admin.owner_only',
          'إدارة الشعارات للمشرف المالك وحده.',
        ),
      );
    }
    return Result.ok(owner);
  }
}
