import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/crests/[slug]/index.dart' as admin_crest;
// ignore: always_use_package_imports
import '../../routes/admin/crests/index.dart' as admin_crests;
// ignore: always_use_package_imports
import '../../routes/crests/index.dart' as manifest_route;
import 'competition_route_harness.dart';

const _base = 'https://ref.supabase.co/storage/v1/object/public/crests/';
const _otherAdmin = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';

final class _Owner implements OwnerNotices {
  const _Owner();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(kAdminId));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Catalog implements CrestCatalog {
  bool enabled = true;
  final Map<String, CrestStatus> status = <String, CrestStatus>{
    'arsenal': CrestStatus.active,
    'milan': CrestStatus.hidden,
  };

  @override
  Future<Result<CrestList>> crests() async => Result.ok(
    CrestList(
      clubsEnabled: enabled,
      crests: <ClubCrest>[
        for (final MapEntry<String, CrestStatus> e in status.entries)
          ClubCrest(
            slug: e.key,
            objectPath: 'clubs/${e.key}.11111111.png',
            status: e.value,
          ),
      ],
    ),
  );

  @override
  Future<Result<List<CrestEvent>>> events({int limit = 50}) async =>
      Result.ok(<CrestEvent>[
        CrestEvent(
          action: 'hidden',
          slug: 'milan',
          reason: 'شكوى',
          at: DateTime.utc(2026, 11, 12, 10),
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
    final CrestStatus? now = status[slug];
    if (now == null || !from.contains(now)) return const Result.ok(false);
    status[slug] = to;
    return const Result.ok(true);
  }

  @override
  Future<Result<void>> setClubsEnabled({
    required bool enabled,
    required String reason,
    required UserId by,
  }) async {
    this.enabled = enabled;
    return const Result.ok(null);
  }
}

final class _Files implements CrestFileEraser {
  final List<String> erased = <String>[];

  @override
  Future<Result<void>> erase(String objectPath) async {
    erased.add(objectPath);
    return const Result.ok(null);
  }
}

/// Script 265: the crests the app may show, and the owner's page, through
/// the real wiring.
void main() {
  late _Catalog catalog;
  late _Files files;

  CompositionRoot root({bool wired = true}) {
    catalog = _Catalog();
    files = _Files();
    return CompositionRoot.forTesting(
      getCrestManifest: wired
          ? GetCrestManifest(catalog: catalog, baseUrl: _base)
          : null,
      ownerCrests: wired
          ? OwnerCrests(
              catalog: catalog,
              files: files,
              owner: const _Owner(),
              baseUrl: _base,
            )
          : null,
    );
  }

  group('GET /crests', () {
    test('a player reads the active crests, tagged by version', () async {
      final response = await manifest_route.onRequest(
        wireContext(
          root: root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['crests'], {'arsenal': '${_base}clubs/arsenal.11111111.png'});
      expect(body['clubs_enabled'], isTrue);
      expect(response.headers[HttpHeaders.etagHeader], '"${body['version']}"');
    });

    test('the same version again is a 304 with no body', () async {
      final r = root();
      final first = await manifest_route.onRequest(
        wireContext(
          root: r,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );
      final String tag = first.headers[HttpHeaders.etagHeader]!;

      final again = await manifest_route.onRequest(
        wireContext(
          root: r,
          principal: userPrincipal(),
          method: HttpMethod.get,
          headers: {HttpHeaders.ifNoneMatchHeader: tag},
        ),
      );

      expect(again.statusCode, HttpStatus.notModified);
      expect(await again.body(), isEmpty);
    });

    test('an unwired root is 503; another method 405', () async {
      final unwired = await manifest_route.onRequest(
        wireContext(
          root: root(wired: false),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );
      final post = await manifest_route.onRequest(
        wireContext(root: root(), principal: userPrincipal()),
      );

      expect(unwired.statusCode, HttpStatus.serviceUnavailable);
      expect(post.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('/admin/crests', () {
    test('the owner reads every crest, its URL and the log', () async {
      final response = await admin_crests.onRequest(
        wireContext(
          root: root(),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );

      final body = await decodeBody(response);
      final crests = (body['crests']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(crests.first['url'], '${_base}clubs/arsenal.11111111.png');
      expect(crests.last['status'], 'hidden');
      expect(
        ((body['events']! as List<Object?>).single! as Map)['slug'],
        'milan',
      );
    });

    test('the owner turns club crests off, with a reason', () async {
      final r = root();

      final response = await admin_crests.onRequest(
        wireContext(
          root: r,
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'clubs_enabled': false, 'reason': 'مراجعة'},
        ),
      );

      expect(await decodeBody(response), {'clubs_enabled': false});
      expect(catalog.enabled, isFalse);
    });

    test('a switch that is not a bool is a 400', () async {
      final response = await admin_crests.onRequest(
        wireContext(
          root: root(),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'clubs_enabled': 'no', 'reason': 'x'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('the owner hides, shows and deletes', () async {
      final r = root();

      Future<Map<String, Object?>> act(String slug, Object body) async =>
          decodeBody(
            await admin_crest.onRequest(
              wireContext(root: r, principal: adminPrincipal(), body: body),
              slug,
            ),
          );

      expect(await act('arsenal', const {'action': 'hide', 'reason': 'شكوى'}), {
        'status': 'hidden',
      });
      expect(await act('arsenal', const {'action': 'show'}), {
        'status': 'active',
      });
      final mistyped = await act('arsenal', const {
        'action': 'delete',
        'reason': 'x',
        'confirm': 'arsena',
      });
      expect(mistyped['code'], 'crest.confirm_mismatch');
      expect(
        await act('arsenal', const {
          'action': 'delete',
          'reason': 'x',
          'confirm': 'arsenal',
        }),
        {'status': 'deleted'},
      );
      expect(files.erased, ['clubs/arsenal.11111111.png']);
      expect(
        (await act('arsenal', const {'action': 'nap'}))['code'],
        'crest.action_invalid',
      );
    });

    test('another admin is refused, nothing changed', () async {
      final r = root();

      final response = await admin_crest.onRequest(
        wireContext(
          root: r,
          principal: const AuthenticatedUser(
            userId: UserId(_otherAdmin),
            role: PlatformRole.admin,
          ),
          body: const {'action': 'hide', 'reason': 'x'},
        ),
        'arsenal',
      );

      expect((await decodeBody(response))['code'], 'admin.owner_only');
      expect(catalog.status['arsenal'], CrestStatus.active);
    });

    test('a player is refused', () async {
      final response = await admin_crests.onRequest(
        wireContext(
          root: root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });
}
