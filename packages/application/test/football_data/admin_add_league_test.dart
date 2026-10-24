/// An admin adds a league the list lacks (script 139, migration 0183)
/// through the real [AdminAddLeague]: the name is folded, a second spelling
/// of a league on file is refused naming it, and every league added is
/// audited.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../admin/fakes.dart' show InMemoryAuditLogRepository;
import '../competition/fakes.dart'
    show FakeIdGenerator, FixedClock, adminPrincipal, userPrincipal;

const _adminId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _playerId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _newLeagueId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _derbiesId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// A scripted [LeagueCatalogWriter] that records what it was asked.
final class _Writer implements LeagueCatalogWriter {
  _Writer(this._answer);

  final Result<LeagueAddition> _answer;
  int calls = 0;
  String? name;

  @override
  Future<Result<LeagueAddition>> add({required String name}) async {
    calls++;
    this.name = name;
    return _answer;
  }
}

League _league(String id, String name) => League(
  id: LeagueRef(id),
  name: name,
  shortName: null,
  logoUrl: null,
  isContinental: true,
);

({AdminAddLeague useCase, _Writer writer, InMemoryAuditLogRepository audit})
_build(Result<LeagueAddition> answer) {
  final writer = _Writer(answer);
  final audit = InMemoryAuditLogRepository();
  final useCase = AdminAddLeague(
    writer: writer,
    auditRecorder: AuditRecorder(
      auditLog: audit,
      idGenerator: FakeIdGenerator(['99999999-9999-4999-8999-999999999999']),
      clock: FixedClock(DateTime.utc(2026, 10, 24, 13)),
    ),
  );
  return (useCase: useCase, writer: writer, audit: audit);
}

void main() {
  group('AdminAddLeague -- a league the list lacks is added to it', () {
    test('the name is folded, the league added, and audited', () async {
      final built = _build(
        Result.ok(
          LeagueAddition(
            league: _league(_newLeagueId, 'كأس السوبر الأفريقي'),
            existed: false,
          ),
        ),
      );

      final result = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: '  كأس   السوبر الأفريقي ',
      );

      final League league = (result as Ok<League>).value;
      expect(league.id.value, _newLeagueId);
      expect(league.isContinental, isTrue);
      expect(built.writer.name, 'كأس السوبر الأفريقي');
      final AuditEntry entry = built.audit.rows.single;
      expect(entry.action, AuditAction.leagueAdded);
      expect(entry.actorId.value, _adminId);
      expect(entry.targetRef, _newLeagueId);
      expect(entry.reason, 'كأس السوبر الأفريقي');
    });

    test('a league already on file is refused by its name, and nothing is '
        'audited', () async {
      final built = _build(
        Result.ok(
          LeagueAddition(
            league: _league(_derbiesId, 'ديربيات كبرى'),
            existed: true,
          ),
        ),
      );

      final result = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: 'ديربيات كبري',
      );

      final AppError error = (result as Err<League>).error;
      expect(error.code, AdminAddLeague.existsCode);
      expect(error.kind, ErrorKind.invariant);
      expect(error.message, contains('«ديربيات كبرى»'));
      expect(built.audit.rows, isEmpty);
    });

    test('an empty or overlong name is refused before anything is '
        'written', () async {
      final built = _build(
        Result.ok(
          LeagueAddition(league: _league(_newLeagueId, 'x'), existed: false),
        ),
      );

      final empty = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: '   ',
      );
      final long = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: 'ن' * (AdminAddLeague.maxNameLength + 1),
      );

      expect((empty as Err<League>).error.code, AdminAddLeague.nameInvalidCode);
      expect((long as Err<League>).error.code, AdminAddLeague.nameInvalidCode);
      expect(built.writer.calls, 0);
    });

    test('a failed write stores nothing and says why', () async {
      final built = _build(
        const Result.err(AppError.transient('db.down', 'down')),
      );

      final result = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: 'دوري جديد',
      );

      expect((result as Err<League>).error.code, 'db.down');
      expect(built.audit.rows, isEmpty);
    });

    test('a player is refused before anything is written', () async {
      final built = _build(
        Result.ok(
          LeagueAddition(league: _league(_newLeagueId, 'x'), existed: false),
        ),
      );

      final result = await built.useCase(
        principal: userPrincipal(_playerId),
        name: 'دوري جديد',
      );

      expect((result as Err<League>).error.kind, ErrorKind.authorization);
      expect(built.writer.calls, 0);
    });
  });
}
