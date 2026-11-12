import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Script 265: the club crests the app may show, and the owner's hands on
/// them.

const String _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _base = 'https://ref.supabase.co/storage/v1/object/public/crests/';

const AuthenticatedUser _ownerUser = AuthenticatedUser(
  userId: UserId(_owner),
  role: PlatformRole.admin,
);
const AuthenticatedUser _otherAdmin = AuthenticatedUser(
  userId: UserId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  role: PlatformRole.admin,
);
const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  role: PlatformRole.user,
);

final class _Owner implements OwnerNotices {
  const _Owner();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Catalog implements CrestCatalog {
  bool enabled = true;
  final Map<String, (String, CrestStatus)> rows =
      <String, (String, CrestStatus)>{
        'arsenal': ('clubs/arsenal.11111111.png', CrestStatus.active),
        'chelsea': ('clubs/chelsea.22222222.png', CrestStatus.active),
        'milan': ('clubs/milan.33333333.png', CrestStatus.hidden),
      };
  final List<(String?, String, String, String?)> log =
      <(String?, String, String, String?)>[];

  @override
  Future<Result<CrestList>> crests() async => Result.ok(
    CrestList(
      clubsEnabled: enabled,
      crests: <ClubCrest>[
        for (final MapEntry<String, (String, CrestStatus)> e in rows.entries)
          ClubCrest(slug: e.key, objectPath: e.value.$1, status: e.value.$2),
      ],
    ),
  );

  @override
  Future<Result<List<CrestEvent>>> events({int limit = 50}) async =>
      Result.ok(<CrestEvent>[
        for (final (slug, action, reason, complainant) in log.reversed)
          CrestEvent(
            action: action,
            slug: slug,
            reason: reason,
            complainant: complainant,
            at: DateTime.utc(2026, 11, 12),
          ),
      ]);

  @override
  Future<Result<bool>> setStatus({
    required String slug,
    required Set<CrestStatus> from,
    required CrestStatus to,
    required String action,
    required String reason,
    required String? complainant,
    required UserId by,
  }) async {
    final (String, CrestStatus)? row = rows[slug];
    if (row == null || !from.contains(row.$2)) return const Result.ok(false);
    rows[slug] = (row.$1, to);
    log.add((slug, action, reason, complainant));
    return const Result.ok(true);
  }

  @override
  Future<Result<void>> setClubsEnabled({
    required bool enabled,
    required String reason,
    required UserId by,
  }) async {
    this.enabled = enabled;
    log.add((null, enabled ? 'clubs_on' : 'clubs_off', reason, null));
    return const Result.ok(null);
  }
}

final class _Files implements CrestFileEraser {
  _Files({this.fails = false});

  final bool fails;
  final List<String> erased = <String>[];

  @override
  Future<Result<void>> erase(String objectPath) async {
    if (fails) return const Result.err(AppError.transient('storage.down', 'x'));
    erased.add(objectPath);
    return const Result.ok(null);
  }
}

void main() {
  group('GetCrestManifest', () {
    test('lists the active crests by URL, for any player', () async {
      final result = await GetCrestManifest(
        catalog: _Catalog(),
        baseUrl: _base,
      )(principal: _player);

      final manifest = (result as Ok<CrestManifest>).value;
      expect(manifest.clubsEnabled, isTrue);
      expect(manifest.crests, <String, String>{
        'arsenal': '${_base}clubs/arsenal.11111111.png',
        'chelsea': '${_base}clubs/chelsea.22222222.png',
      });
      expect(manifest.version, hasLength(8));
    });

    test('the version moves with the list, and only with it', () async {
      final catalog = _Catalog();
      final GetCrestManifest read = GetCrestManifest(
        catalog: catalog,
        baseUrl: _base,
      );

      final first = (await read(principal: _player) as Ok<CrestManifest>);
      final again = (await read(principal: _player) as Ok<CrestManifest>);
      catalog.rows['chelsea'] = (
        'clubs/chelsea.22222222.png',
        CrestStatus.hidden,
      );
      final changed = (await read(principal: _player) as Ok<CrestManifest>);

      expect(again.value.version, first.value.version);
      expect(changed.value.version, isNot(first.value.version));
    });

    test('with club crests off, or no bucket address, nothing', () async {
      final off = _Catalog()..enabled = false;

      final none = await GetCrestManifest(catalog: off, baseUrl: _base)(
        principal: _player,
      );
      final noBase = await GetCrestManifest(catalog: _Catalog())(
        principal: _player,
      );

      expect((none as Ok<CrestManifest>).value.crests, isEmpty);
      expect(none.value.clubsEnabled, isFalse);
      expect((noBase as Ok<CrestManifest>).value.crests, isEmpty);
    });
  });

  group('OwnerCrests', () {
    late _Catalog catalog;
    late _Files files;
    late OwnerCrests crests;

    setUp(() {
      catalog = _Catalog();
      files = _Files();
      crests = OwnerCrests(
        catalog: catalog,
        files: files,
        owner: const _Owner(),
      );
    });

    test(
      'the owner hides a crest for a complaint, and shows it again',
      () async {
        final hidden = await crests.hide(
          principal: _ownerUser,
          slug: 'arsenal',
          reason: 'شكوى من النادي',
          complainant: 'legal@arsenal.example',
        );
        final shown = await crests.show(principal: _ownerUser, slug: 'arsenal');

        expect(hidden, isA<Ok<void>>());
        expect(shown, isA<Ok<void>>());
        expect(catalog.log.first, (
          'arsenal',
          'hidden',
          'شكوى من النادي',
          'legal@arsenal.example',
        ));
        expect(catalog.log.last.$3, 'أُعيد إظهاره');
        expect(catalog.rows['arsenal']!.$2, CrestStatus.active);
      },
    );

    test('a reason is required', () async {
      final result = await crests.hide(
        principal: _ownerUser,
        slug: 'arsenal',
        reason: '  ',
      );

      expect((result as Err<void>).error.code, 'crest.reason_required');
      expect(catalog.log, isEmpty);
    });

    test('hiding a hidden crest, or an unknown one, is refused', () async {
      final again = await crests.hide(
        principal: _ownerUser,
        slug: 'milan',
        reason: 'x',
      );
      final unknown = await crests.hide(
        principal: _ownerUser,
        slug: 'nope',
        reason: 'x',
      );

      expect((again as Err<void>).error.code, 'crest.state');
      expect((unknown as Err<void>).error.code, 'crest.not_found');
    });

    test('a delete needs the name typed, then erases the file', () async {
      final mistyped = await crests.delete(
        principal: _ownerUser,
        slug: 'chelsea',
        confirm: 'chelse',
        reason: 'طلب حذف',
      );
      final deleted = await crests.delete(
        principal: _ownerUser,
        slug: 'chelsea',
        confirm: 'chelsea',
        reason: 'طلب حذف',
        complainant: 'club',
      );

      expect((mistyped as Err<void>).error.code, 'crest.confirm_mismatch');
      expect(deleted, isA<Ok<void>>());
      expect(files.erased, <String>['clubs/chelsea.22222222.png']);
      expect(catalog.rows['chelsea']!.$2, CrestStatus.deleted);
      final again = await crests.delete(
        principal: _ownerUser,
        slug: 'chelsea',
        confirm: 'chelsea',
        reason: 'x',
      );
      expect((again as Err<void>).error.code, 'crest.state');
    });

    test('a file that cannot be erased leaves the crest as it was', () async {
      final failing = OwnerCrests(
        catalog: catalog,
        files: _Files(fails: true),
        owner: const _Owner(),
      );

      final result = await failing.delete(
        principal: _ownerUser,
        slug: 'arsenal',
        confirm: 'arsenal',
        reason: 'x',
      );

      expect((result as Err<void>).error.code, 'storage.down');
      expect(catalog.rows['arsenal']!.$2, CrestStatus.active);
    });

    test('the owner turns club crests off, with a reason', () async {
      final off = await crests.setClubsEnabled(
        principal: _ownerUser,
        enabled: false,
        reason: 'مراجعة',
      );

      expect(off, isA<Ok<void>>());
      expect(catalog.enabled, isFalse);
      expect(catalog.log.single.$2, 'clubs_off');
    });

    test('the owner reads the crests and the log', () async {
      await crests.hide(principal: _ownerUser, slug: 'arsenal', reason: 'x');

      final state = await crests.state(principal: _ownerUser);

      final value = (state as Ok<CrestState>).value;
      expect(value.list.crests, hasLength(3));
      expect(value.events.single.action, 'hidden');
    });

    test('another admin and a player are refused, nothing changed', () async {
      final other = await crests.hide(
        principal: _otherAdmin,
        slug: 'arsenal',
        reason: 'x',
      );
      final player = await crests.state(principal: _player);

      expect((other as Err<void>).error.code, 'admin.owner_only');
      expect((player as Err<CrestState>).error.code, 'auth.insufficient_role');
      expect(catalog.log, isEmpty);
    });
  });
}
