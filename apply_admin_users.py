#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
يطبّق ميزة بحث/تصفح الأعضاء (GET /admin/users) على مستودع نُخبة.
شغّله من جذر المستودع (المجلد الذي يحوي apps/ و packages/):
    python3 apply_admin_users_feature.py
"""
import sys
from pathlib import Path

ROOT = Path(".").resolve()

def fail(msg):
    print(f"❌ {msg}")
    sys.exit(1)

def replace_once(path_str, old, new):
    p = ROOT / path_str
    if not p.exists():
        fail(f"الملف غير موجود: {path_str}")
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count == 0:
        fail(f"النص المطلوب استبداله غير موجود (ربما طُبّق سابقًا؟): {path_str}")
    if count > 1:
        fail(f"النص يتكرر {count} مرات (غير آمن للاستبدال التلقائي): {path_str}")
    p.write_text(text.replace(old, new), encoding="utf-8")
    print(f"✅ عُدّل: {path_str}")

def create_new(path_str, content):
    p = ROOT / path_str
    if p.exists():
        print(f"⏭️  موجود بالفعل، تم تخطيه: {path_str}")
        return
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    print(f"✅ أُنشئ: {path_str}")

# ---------------------------------------------------------------------------
# 1) ملفات جديدة
# ---------------------------------------------------------------------------

create_new(
    "packages/application/lib/src/admin/list_users.dart",
    """import 'package:application/src/admin/ports/user_admin_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: browse platform users by an optional case-insensitive
/// email-contains [search] — the admin \"find a user to sanction\" flow
/// (admin-only, Security ADR §2.2/§2.3).
///
/// 1. authorize the caller as [PlatformRole.admin];
/// 2. clamp an untrusted [limit] to `[1, maxLimit]`;
/// 3. normalize a blank [search] to `null` (browse-all, still bounded);
/// 4. delegate to [UserAdminRepository.listUsers].
///
/// An empty match is a legitimate empty result, never an error. Never throws.
final class ListUsers {
  const ListUsers({required UserAdminRepository users}) : _users = users;

  final UserAdminRepository _users;

  static const int defaultLimit = 20;
  static const int maxLimit = 50;

  Future<Result<List<User>>> call({
    required AuthenticatedUser principal,
    String? search,
    int? limit,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final trimmed = search?.trim();
    return _users.listUsers(
      search: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      limit: _clampLimit(limit),
    );
  }

  static int _clampLimit(int? limit) {
    if (limit == null || limit <= 0) return defaultLimit;
    if (limit > maxLimit) return maxLimit;
    return limit;
  }
}
""",
)

create_new(
    "apps/server/routes/admin/users/index.dart",
    """import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/users` — browse platform users by an optional email-contains
/// `search`. Admin-only (gate inside `ListUsers`). `?limit=` clamps
/// server-side. Returns [UserListDto] (`200`); empty `users` is legitimate.
/// `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final query = context.request.uri.queryParameters;
  final rawLimit = query['limit'];
  final limit = rawLimit == null ? null : int.tryParse(rawLimit);

  final result = await root.listUsers(
    principal: principal,
    search: query['search'],
    limit: limit,
  );

  return switch (result) {
    Ok<List<User>>(:final value) => Response.json(body: userListJson(value)),
    Err<List<User>>(:final error) => errorResponse(error),
  };
}
""",
)

# ---------------------------------------------------------------------------
# 2) تعديلات على ملفات موجودة
# ---------------------------------------------------------------------------

replace_once(
    "packages/application/lib/src/admin/ports/user_admin_repository.dart",
    "  Future<Result<User>> updateUser(User user);\n}",
    "  Future<Result<User>> updateUser(User user);\n\n"
    "  /// Browses users by an optional case-insensitive email-contains [search],\n"
    "  /// capped at [limit], ordered by email. The admin surface's find-a-user\n"
    "  /// read.\n"
    "  Future<Result<List<User>>> listUsers({String? search, required int limit});\n}",
)

replace_once(
    "packages/application/lib/application.dart",
    "export 'src/admin/list_audit_log.dart';",
    "export 'src/admin/list_audit_log.dart';\nexport 'src/admin/list_users.dart';",
)

replace_once(
    "packages/infrastructure/lib/src/admin/postgres_user_admin_repository.dart",
    "  // --------------------------------------------------------------------------\n"
    "  // Row mapping (mirrors PostgresUserDirectory._mapSingleRow)\n"
    "  // --------------------------------------------------------------------------",
    "  // --------------------------------------------------------------------------\n"
    "  // listUsers — browse by optional email-contains search\n"
    "  // --------------------------------------------------------------------------\n"
    "\n"
    "  static const String _listSql = '''\n"
    "SELECT id, email, role::text, status::text\n"
    "FROM identity.users\n"
    "WHERE (@search::text IS NULL OR email ILIKE @search)\n"
    "ORDER BY email ASC\n"
    "LIMIT @limit\n"
    "''';\n"
    "\n"
    "  @override\n"
    "  Future<Result<List<User>>> listUsers({\n"
    "    String? search,\n"
    "    required int limit,\n"
    "  }) async {\n"
    "    final pattern = search == null ? null : '%${_escapeLike(search)}%';\n"
    "    final result = await _connection.query(\n"
    "      _listSql,\n"
    "      parameters: {'search': pattern, 'limit': limit},\n"
    "    );\n"
    "    return switch (result) {\n"
    "      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),\n"
    "      Ok<List<Map<String, dynamic>>>(:final value) => _mapMany(value),\n"
    "    };\n"
    "  }\n"
    "\n"
    "  Result<List<User>> _mapMany(List<Map<String, dynamic>> rows) {\n"
    "    final users = <User>[];\n"
    "    for (final row in rows) {\n"
    "      final mapped = _mapOne(row);\n"
    "      if (mapped is Err<User>) return Result.err(mapped.error);\n"
    "      users.add((mapped as Ok<User>).value);\n"
    "    }\n"
    "    return Result.ok(List<User>.unmodifiable(users));\n"
    "  }\n"
    "\n"
    "  // Escapes ILIKE metacharacters so a search term is matched literally\n"
    "  // (Postgres' default LIKE/ILIKE escape char is backslash).\n"
    r"  static String _escapeLike(String raw) => raw" "\n"
    r"      .replaceAll(r'\', r'\\')" "\n"
    r"      .replaceAll('%', r'\%')" "\n"
    r"      .replaceAll('_', r'\_');" "\n"
    "\n"
    "  // --------------------------------------------------------------------------\n"
    "  // Row mapping (mirrors PostgresUserDirectory._mapSingleRow)\n"
    "  // --------------------------------------------------------------------------",
)

replace_once(
    "packages/contracts/lib/src/admin_dto.dart",
    "/// The wire shape of one immutable admin audit record (read projection of the",
    """/// One row of `GET /admin/users` — a minimal user summary for the admin
/// find-a-user flow. Carries only what the sanction UI needs: [id] (to fill
/// the target-user field), [email] (nullable — provider-sourced, may be
/// absent), and [status]. No role field: the browse surface has no authority
/// over role.
final class UserSummaryDto {
  /// Creates a user-summary DTO.
  const UserSummaryDto({
    required this.id,
    required this.status,
    this.email,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory UserSummaryDto.fromJson(Map<String, Object?> json) {
    return UserSummaryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      email: json['email'] as String?,
      status: json['status']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The user's id (UUID string).
  final String id;

  /// The user's email, when known. Omitted from JSON when `null`.
  final String? email;

  /// The user's lifecycle status (`active` / `suspended`).
  final String status;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    if (email != null) 'email': email,
    'status': status,
  };

  @override
  bool operator ==(Object other) =>
      other is UserSummaryDto &&
      other.id == id &&
      other.email == email &&
      other.status == status &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(id, email, status, schemaVersion);
}

/// The wire shape of `GET /admin/users` — a bounded, server-ordered browse
/// result. An empty [users] list is a legitimate empty match, never an error.
final class UserListDto {
  /// Creates a user-list DTO.
  const UserListDto({
    required this.users,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory UserListDto.fromJson(Map<String, Object?> json) {
    final raw = json['users']! as List<Object?>;
    return UserListDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      users: raw
          .map(
            (e) => UserSummaryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The matching users, server-ordered.
  final List<UserSummaryDto> users;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'users': [for (final u in users) u.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is UserListDto &&
      _userListEquals(other.users, users) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(Object.hashAll(users), schemaVersion);

  static bool _userListEquals(
    List<UserSummaryDto> a,
    List<UserSummaryDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The wire shape of one immutable admin audit record (read projection of the""",
)

replace_once(
    "apps/server/lib/http/admin_dto_mapper.dart",
    "/// Projects one immutable [AuditEntry] onto the wire [AuditEntryDto].",
    """/// Projects one [User] onto the wire [UserSummaryDto] — a row of
/// `GET /admin/users`.
UserSummaryDto userSummaryToDto(User user) => UserSummaryDto(
  id: user.id.value,
  email: user.email,
  status: user.status.name,
);

/// Shapes the response of `GET /admin/users`. An empty list is a legitimate
/// empty match, never an error.
Map<String, Object?> userListJson(List<User> users) =>
    UserListDto(users: [for (final u in users) userSummaryToDto(u)]).toJson();

/// Projects one immutable [AuditEntry] onto the wire [AuditEntryDto].""",
)

replace_once(
    "packages/api_client/lib/src/admin_api.dart",
    "  /// `POST /admin/users/{userId}/suspend` — suspends a user, with a",
    """  /// `GET /admin/users` — browse users by an optional email-contains
  /// [search]; [limit] is an optional page cap, clamped server-side.
  Future<Result<UserListDto>> listUsers({String? search, int? limit}) {
    final query = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (limit != null) 'limit': '$limit',
    };
    return _transport.getObject<UserListDto>(
      '/admin/users',
      query: query.isEmpty ? null : query,
      parse: UserListDto.fromJson,
    );
  }

  /// `POST /admin/users/{userId}/suspend` — suspends a user, with a""",
)

CR = "apps/server/lib/composition/composition_root.dart"

replace_once(
    CR,
    "    required this.suspendUser,\n"
    "    required this.reinstateUser,\n"
    "    required this.listAuditLog,\n"
    "    required this.viewParticipantLedger,\n"
    "  }) : _connection = connection,",
    "    required this.suspendUser,\n"
    "    required this.reinstateUser,\n"
    "    required this.listUsers,\n"
    "    required this.listAuditLog,\n"
    "    required this.viewParticipantLedger,\n"
    "  }) : _connection = connection,",
)

replace_once(
    CR,
    "    SuspendUser? suspendUser,\n"
    "    ReinstateUser? reinstateUser,\n"
    "    ListAuditLog? listAuditLog,",
    "    SuspendUser? suspendUser,\n"
    "    ReinstateUser? reinstateUser,\n"
    "    ListUsers? listUsers,\n"
    "    ListAuditLog? listAuditLog,",
)

replace_once(
    CR,
    "       suspendUser = suspendUser ?? _absentSuspendUser(),\n"
    "       reinstateUser = reinstateUser ?? _absentReinstateUser(),\n"
    "       listAuditLog = listAuditLog ?? _absentListAuditLog(),",
    "       suspendUser = suspendUser ?? _absentSuspendUser(),\n"
    "       reinstateUser = reinstateUser ?? _absentReinstateUser(),\n"
    "       listUsers = listUsers ?? _absentListUsers(),\n"
    "       listAuditLog = listAuditLog ?? _absentListAuditLog(),",
)

replace_once(
    CR,
    "  static ListAuditLog _absentListAuditLog() =>\n"
    "      ListAuditLog(auditLog: _unwiredAuditLogRepository);",
    "  static ListUsers _absentListUsers() =>\n"
    "      ListUsers(users: _unwiredUserAdminRepository);\n"
    "\n"
    "  static ListAuditLog _absentListAuditLog() =>\n"
    "      ListAuditLog(auditLog: _unwiredAuditLogRepository);",
)

replace_once(
    CR,
    "  final ReinstateUser reinstateUser;\n"
    "\n"
    "  /// Reads the append-only admin audit trail, newest-first (admin-only — the",
    "  final ReinstateUser reinstateUser;\n"
    "\n"
    "  /// Browses platform users by an optional email-contains search — the admin\n"
    "  /// find-a-user flow feeding [suspendUser]/[reinstateUser] (admin-only).\n"
    "  final ListUsers listUsers;\n"
    "\n"
    "  /// Reads the append-only admin audit trail, newest-first (admin-only — the",
)

replace_once(
    CR,
    "      listAuditLog: ListAuditLog(auditLog: auditLogRepository),",
    "      listUsers: ListUsers(users: userAdminRepository),\n"
    "      listAuditLog: ListAuditLog(auditLog: auditLogRepository),",
)

replace_once(
    CR,
    "  @override\n"
    "  Future<Result<User>> updateUser(User user) => _unwired();\n"
    "}",
    "  @override\n"
    "  Future<Result<User>> updateUser(User user) => _unwired();\n"
    "\n"
    "  @override\n"
    "  Future<Result<List<User>>> listUsers({\n"
    "    String? search,\n"
    "    required int limit,\n"
    "  }) => _unwired();\n"
    "}",
)

FAKE_BODY = """
  @override
  Future<Result<List<User>>> listUsers({{
    String? search,
    required int limit,
  }}) async {{
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final all = {values}.toList()
      ..sort((a, b) => (a.email ?? '').compareTo(b.email ?? ''));
    final matched = search == null
        ? all
        : all
              .where(
                (u) => (u.email ?? '').toLowerCase().contains(
                  search.toLowerCase(),
                ),
              )
              .toList();
    final capped = matched.length > limit
        ? matched.sublist(0, limit)
        : matched;
    return Result.ok(List<User>.unmodifiable(capped));
  }}
}}"""

replace_once(
    "packages/application/test/admin/fakes.dart",
    "  @override\n"
    "  Future<Result<User>> updateUser(User user) async {\n"
    "    final f = _takeFailure();\n"
    "    if (f != null) return Result.err(f);\n"
    "    _byId[user.id.value] = user;\n"
    "    return Result.ok(user);\n"
    "  }\n"
    "}",
    "  @override\n"
    "  Future<Result<User>> updateUser(User user) async {\n"
    "    final f = _takeFailure();\n"
    "    if (f != null) return Result.err(f);\n"
    "    _byId[user.id.value] = user;\n"
    "    return Result.ok(user);\n"
    "  }\n"
    + FAKE_BODY.format(values="_byId.values"),
)

replace_once(
    "apps/server/test/routes/competition_route_harness.dart",
    "  @override\n"
    "  Future<Result<User>> updateUser(User user) async {\n"
    "    final f = _takeFailure();\n"
    "    if (f != null) return Result.err(f);\n"
    "    users[user.id.value] = user;\n"
    "    return Result.ok(user);\n"
    "  }\n"
    "}",
    "  @override\n"
    "  Future<Result<User>> updateUser(User user) async {\n"
    "    final f = _takeFailure();\n"
    "    if (f != null) return Result.err(f);\n"
    "    users[user.id.value] = user;\n"
    "    return Result.ok(user);\n"
    "  }\n"
    + FAKE_BODY.format(values="users.values"),
)

replace_once(
    "apps/mobile/lib/features/admin/admin_providers.dart",
    "/// Owns the narrow cross-user ledger support-read",
    """/// Owns the users browse/search read (`GET /admin/users`), used to find a
/// target user id for the sanction fields. Modelled as a controller (rather
/// than a `FutureProvider`) since a search is an explicit admin action, not a
/// passive view a screen loads on entry.
@riverpod
class UsersLookupController extends _$UsersLookupController {
  AdminApi get _api => ref.read(adminApiProvider);

  @override
  AsyncValue<UserListDto>? build() => null;

  /// Searches users by an optional email-contains [search].
  Future<void> search(String search) async {
    state = const AsyncValue.loading();
    final result = await _api.listUsers(search: search);
    state = switch (result) {
      Ok<UserListDto>(:final value) => AsyncValue.data(value),
      Err<UserListDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the narrow cross-user ledger support-read""",
)

DASH = "apps/mobile/lib/features/admin/admin_dashboard_screen.dart"

replace_once(
    DASH,
    "class _UserSanctionTabState extends ConsumerState<_UserSanctionTab> {\n"
    "  final TextEditingController _userIdController = TextEditingController();\n"
    "  final TextEditingController _reasonController = TextEditingController();\n"
    "\n"
    "  @override\n"
    "  void dispose() {\n"
    "    _userIdController.dispose();\n"
    "    _reasonController.dispose();\n"
    "    super.dispose();\n"
    "  }\n"
    "\n"
    "  @override\n"
    "  Widget build(BuildContext context) {\n"
    "    final l10n = AppLocalizations.of(context);\n"
    "    final AsyncValue<UserSanctionResultDto>? state = ref.watch(\n"
    "      userSanctionControllerProvider,\n"
    "    );\n"
    "    final bool inFlight = state is AsyncLoading<UserSanctionResultDto>;\n"
    "    final AppTokens tokens = context.tokens;\n"
    "    return Padding(\n"
    "      padding: const EdgeInsets.all(AppSpacing.xl),\n"
    "      child: Column(\n"
    "        crossAxisAlignment: CrossAxisAlignment.stretch,\n"
    "        children: <Widget>[\n"
    "          TextField(\n"
    "            key: const Key('admin.users.userIdField'),",
    "class _UserSanctionTabState extends ConsumerState<_UserSanctionTab> {\n"
    "  final TextEditingController _userIdController = TextEditingController();\n"
    "  final TextEditingController _reasonController = TextEditingController();\n"
    "  final TextEditingController _searchController = TextEditingController();\n"
    "\n"
    "  @override\n"
    "  void dispose() {\n"
    "    _userIdController.dispose();\n"
    "    _reasonController.dispose();\n"
    "    _searchController.dispose();\n"
    "    super.dispose();\n"
    "  }\n"
    "\n"
    "  void _search() {\n"
    "    ref\n"
    "        .read(usersLookupControllerProvider.notifier)\n"
    "        .search(_searchController.text.trim());\n"
    "  }\n"
    "\n"
    "  @override\n"
    "  Widget build(BuildContext context) {\n"
    "    final l10n = AppLocalizations.of(context);\n"
    "    final AsyncValue<UserSanctionResultDto>? state = ref.watch(\n"
    "      userSanctionControllerProvider,\n"
    "    );\n"
    "    final AsyncValue<UserListDto>? search = ref.watch(\n"
    "      usersLookupControllerProvider,\n"
    "    );\n"
    "    final bool inFlight = state is AsyncLoading<UserSanctionResultDto>;\n"
    "    final bool searching = search is AsyncLoading<UserListDto>;\n"
    "    final AppTokens tokens = context.tokens;\n"
    "    return Padding(\n"
    "      padding: const EdgeInsets.all(AppSpacing.xl),\n"
    "      child: Column(\n"
    "        crossAxisAlignment: CrossAxisAlignment.stretch,\n"
    "        children: <Widget>[\n"
    "          Row(\n"
    "            children: <Widget>[\n"
    "              Expanded(\n"
    "                child: TextField(\n"
    "                  key: const Key('admin.users.searchField'),\n"
    "                  controller: _searchController,\n"
    "                  decoration: InputDecoration(\n"
    "                    labelText: l10n.adminUsersSearchLabel,\n"
    "                    border: const OutlineInputBorder(),\n"
    "                  ),\n"
    "                  enabled: !searching,\n"
    "                  onSubmitted: (_) => _search(),\n"
    "                ),\n"
    "              ),\n"
    "              const SizedBox(width: AppSpacing.md),\n"
    "              FilledButton(\n"
    "                key: const Key('admin.users.searchButton'),\n"
    "                onPressed: searching ? null : _search,\n"
    "                child: Text(l10n.adminLookUpButton),\n"
    "              ),\n"
    "            ],\n"
    "          ),\n"
    "          if (search != null)\n"
    "            SizedBox(\n"
    "              height: 200,\n"
    "              child: AsyncListView<UserSummaryDto>(\n"
    "                value: search.whenData((dto) => dto.users),\n"
    "                emptyMessage: l10n.adminUsersEmptyResults,\n"
    "                onRetry: _search,\n"
    "                itemBuilder: (context, user) => ListTile(\n"
    "                  key: Key('admin.users.result.${user.id}'),\n"
    "                  title: Text(user.email ?? user.id),\n"
    "                  subtitle: Text(user.status),\n"
    "                  onTap: () =>\n"
    "                      setState(() => _userIdController.text = user.id),\n"
    "                ),\n"
    "              ),\n"
    "            ),\n"
    "          const SizedBox(height: AppSpacing.lg),\n"
    "          TextField(\n"
    "            key: const Key('admin.users.userIdField'),",
)

replace_once(
    DASH,
    "              child: Text(\n"
    "                '${state.value.userId} is now ${state.value.status}',\n"
    "                key: const Key('admin.users.result'),\n"
    "              ),",
    "              child: Text(\n"
    "                l10n.adminSanctionResultMessage(\n"
    "                  state.value.userId,\n"
    "                  state.value.status,\n"
    "                ),\n"
    "                key: const Key('admin.users.result'),\n"
    "              ),",
)

replace_once(
    "apps/mobile/lib/l10n/app_ar.arb",
    '  "adminReinstateButton": "إعادة تفعيل",',
    '  "adminReinstateButton": "إعادة تفعيل",\n'
    '  "adminUsersSearchLabel": "ابحث بالبريد الإلكتروني",\n'
    '  "adminUsersEmptyResults": "لا يوجد مستخدمون مطابقون.",\n'
    '  "adminSanctionResultMessage": "المستخدم {userId} أصبح الآن {status}",',
)

replace_once(
    "apps/mobile/lib/l10n/app_en.arb",
    '  "adminReinstateButton": "Reinstate",',
    '  "adminReinstateButton": "Reinstate",\n'
    '  "adminUsersSearchLabel": "Search by email",\n'
    '  "adminUsersEmptyResults": "No matching users.",\n'
    '  "adminSanctionResultMessage": "{userId} is now {status}",\n'
    '  "@adminSanctionResultMessage": {\n'
    '    "description": "Result line after a suspend/reinstate action.",\n'
    '    "placeholders": {\n'
    '      "userId": {"type": "String"},\n'
    '      "status": {"type": "String"}\n'
    "    }\n"
    "  },",
)

print("\n🎉 تم تطبيق كل التعديلات بنجاح.")
print("التالي: cd apps/mobile && dart run build_runner build --delete-conflicting-outputs")
