import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/duplicate-names/index.dart' as duplicates_route;
// ignore: always_use_package_imports
import '../../routes/admin/users/[id]/display-name/index.dart' as rename_route;
import 'competition_route_harness.dart';

/// A directory over one stored account. Writing a [taken] name fails the way
/// the database does since migration 0084.
final class _Directory implements UserDirectory {
  _Directory(this.current);

  User current;
  final Set<String> taken = {};

  @override
  Future<Result<User?>> findUser(UserId id) async =>
      Result.ok(id == current.id ? current : null);

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async {
    if (taken.contains(displayName)) {
      return const Result.err(
        AppError.validation(
          'identity.display_name_taken',
          'هذا الاسم مستخدم، اختر اسمًا آخر',
        ),
      );
    }
    current = User(
      id: current.id,
      email: current.email,
      role: current.role,
      status: current.status,
      displayName: displayName,
    );
    return Result.ok(current);
  }

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> clearAvatar(UserId userId) => throw UnimplementedError();

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw UnimplementedError();
}

final class _Reader implements DuplicateNameReader {
  _Reader(this.groups);

  final List<DuplicateNameGroup> groups;

  @override
  Future<Result<List<DuplicateNameGroup>>> duplicateNames({
    required int limit,
  }) async => Result.ok(groups);
}

void main() {
  group('POST /admin/users/{id}/display-name', () {
    late _Directory directory;
    late InMemoryAuditLogRepository audit;
    late CompositionRoot root;

    setUp(() {
      directory = _Directory(storedUser());
      audit = InMemoryAuditLogRepository();
      root = CompositionRoot.forTesting(
        adminRenameUser: AdminRenameUser(
          userDirectory: directory,
          auditRecorder: AuditRecorder(
            auditLog: audit,
            idGenerator: ScriptedIdGenerator([kAuditEntryId]),
            clock: FixedClock(DateTime.utc(2026, 10, 2, 12)),
          ),
        ),
      );
    });

    Future<Response> rename(
      AuthenticatedUser principal,
      Object? body, {
      HttpMethod method = HttpMethod.post,
    }) => rename_route.onRequest(
      wireContext(root: root, principal: principal, method: method, body: body),
      kTargetUserId,
    );

    test('an admin renames the account and the change is audited', () async {
      final response = await rename(adminPrincipal(), {
        'display_name': 'أحمد الثاني',
        'reason': 'اسم مكرر',
      });

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['id'], kTargetUserId);
      expect(body['display_name'], 'أحمد الثاني');
      expect(directory.current.displayName, 'أحمد الثاني');
      expect(audit.entries.single.action, AuditAction.userRenamed);
    });

    test('a name another player holds is 400 display_name_taken', () async {
      directory.taken.add('خالد');

      final response = await rename(adminPrincipal(), {
        'display_name': 'خالد',
        'reason': 'اسم مكرر',
      });

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        (await decodeBody(response))['code'],
        'identity.display_name_taken',
      );
      expect(audit.entries, isEmpty);
    });

    test('a missing reason is 400 and nothing changes', () async {
      final response = await rename(adminPrincipal(), {'display_name': 'خالد'});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        (await decodeBody(response))['code'],
        'admin.rename_reason_required',
      );
      expect(directory.current.displayName, 'Human');
    });

    test('a player is refused', () async {
      final response = await rename(userPrincipal(), {
        'display_name': 'خالد',
        'reason': 'x',
      });

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(directory.current.displayName, 'Human');
    });

    test('any other method is 405', () async {
      final response = await rename(
        adminPrincipal(),
        null,
        method: HttpMethod.get,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('GET /admin/duplicate-names', () {
    Future<Response> list(
      AuthenticatedUser principal, {
      List<DuplicateNameGroup> groups = const [],
      HttpMethod method = HttpMethod.get,
    }) => duplicates_route.onRequest(
      wireContext(
        root: CompositionRoot.forTesting(
          adminListDuplicateNames: AdminListDuplicateNames(
            names: _Reader(groups),
          ),
        ),
        principal: principal,
        method: method,
      ),
    );

    test('an admin reads every group with its accounts', () async {
      final response = await list(
        adminPrincipal(),
        groups: [
          DuplicateNameGroup([
            storedUser(),
            storedUser(id: kUserId, status: UserStatus.suspended),
          ]),
        ],
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final groups = body['groups']! as List<Object?>;
      final users =
          (groups.single! as Map<String, Object?>)['users']! as List<Object?>;
      expect(users, hasLength(2));
      expect((users.last! as Map<String, Object?>)['status'], 'suspended');
    });

    test('a player is refused', () async {
      final response = await list(userPrincipal());

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('any other method is 405', () async {
      final response = await list(adminPrincipal(), method: HttpMethod.post);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
