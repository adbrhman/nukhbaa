/// An admin adds a club the list lacks (script 91, migration 0173) through
/// the real [AdminAddTeam]: the name is folded and filed under the league
/// picked, a second spelling of a club on file is refused naming it, and
/// every club added is audited.
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
const _leagueId = 'abababab-abab-4bab-8bab-abababababab';
const _newTeamId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _besiktasId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// A scripted [TeamCatalogWriter] that records what it was asked.
final class _Writer implements TeamCatalogWriter {
  _Writer(this._answer);

  final Result<TeamAddition> _answer;
  int calls = 0;
  String? name;
  LeagueRef? leagueId;

  @override
  Future<Result<TeamAddition>> add({
    required String name,
    required LeagueRef? leagueId,
  }) async {
    calls++;
    this.name = name;
    this.leagueId = leagueId;
    return _answer;
  }
}

Team _team(String id, String name, {String? leagueId}) => Team(
  id: TeamRef(id),
  name: name,
  shortName: null,
  crestUrl: null,
  leagueId: leagueId == null ? null : LeagueRef(leagueId),
);

({AdminAddTeam useCase, _Writer writer, InMemoryAuditLogRepository audit})
_build(Result<TeamAddition> answer) {
  final writer = _Writer(answer);
  final audit = InMemoryAuditLogRepository();
  final useCase = AdminAddTeam(
    writer: writer,
    auditRecorder: AuditRecorder(
      auditLog: audit,
      idGenerator: FakeIdGenerator(['99999999-9999-4999-8999-999999999999']),
      clock: FixedClock(DateTime.utc(2026, 10, 16, 13)),
    ),
  );
  return (useCase: useCase, writer: writer, audit: audit);
}

void main() {
  group('AdminAddTeam -- a club the list lacks is added to it', () {
    test('the name is folded, filed under the league, and audited', () async {
      final built = _build(
        Result.ok(
          TeamAddition(
            team: _team(_newTeamId, 'نادي جديد', leagueId: _leagueId),
            existed: false,
          ),
        ),
      );

      final result = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: '  نادي   جديد ',
        leagueId: _leagueId,
      );

      final Team team = (result as Ok<Team>).value;
      expect(team.id.value, _newTeamId);
      expect(built.writer.name, 'نادي جديد');
      expect(built.writer.leagueId?.value, _leagueId);
      final AuditEntry entry = built.audit.rows.single;
      expect(entry.action, AuditAction.teamAdded);
      expect(entry.actorId.value, _adminId);
      expect(entry.targetRef, _newTeamId);
      expect(entry.reason, 'نادي جديد');
    });

    test('no league is a club filed under none', () async {
      final built = _build(
        Result.ok(
          TeamAddition(team: _team(_newTeamId, 'نادي جديد'), existed: false),
        ),
      );

      final result = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: 'نادي جديد',
      );

      expect(result, isA<Ok<Team>>());
      expect(built.writer.leagueId, isNull);
    });

    test('a club already on file is refused by its name, and nothing is '
        'audited', () async {
      final built = _build(
        Result.ok(
          TeamAddition(team: _team(_besiktasId, 'بشكتاش'), existed: true),
        ),
      );

      final result = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: 'بشكتاش',
      );

      final AppError error = (result as Err<Team>).error;
      expect(error.code, AdminAddTeam.existsCode);
      expect(error.kind, ErrorKind.invariant);
      expect(error.message, contains('«بشكتاش»'));
      expect(built.audit.rows, isEmpty);
    });

    test('an empty or overlong name is refused before anything is '
        'written', () async {
      final built = _build(
        Result.ok(TeamAddition(team: _team(_newTeamId, 'x'), existed: false)),
      );

      final empty = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: '   ',
      );
      final long = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: 'ن' * (AdminAddTeam.maxNameLength + 1),
      );

      expect((empty as Err<Team>).error.code, AdminAddTeam.nameInvalidCode);
      expect((long as Err<Team>).error.code, AdminAddTeam.nameInvalidCode);
      expect(built.writer.calls, 0);
    });

    test(
      'a malformed league id is refused before anything is written',
      () async {
        final built = _build(
          Result.ok(TeamAddition(team: _team(_newTeamId, 'x'), existed: false)),
        );

        final result = await built.useCase(
          principal: adminPrincipal(_adminId),
          name: 'نادي جديد',
          leagueId: 'not-a-uuid',
        );

        expect((result as Err<Team>).error.kind, ErrorKind.validation);
        expect(built.writer.calls, 0);
      },
    );

    test('a failed write stores nothing and says why', () async {
      final built = _build(
        const Result.err(AppError.transient('db.down', 'down')),
      );

      final result = await built.useCase(
        principal: adminPrincipal(_adminId),
        name: 'نادي جديد',
      );

      expect((result as Err<Team>).error.code, 'db.down');
      expect(built.audit.rows, isEmpty);
    });

    test('a player is refused before anything is written', () async {
      final built = _build(
        Result.ok(TeamAddition(team: _team(_newTeamId, 'x'), existed: false)),
      );

      final result = await built.useCase(
        principal: userPrincipal(_playerId),
        name: 'نادي جديد',
      );

      expect((result as Err<Team>).error.kind, ErrorKind.authorization);
      expect(built.writer.calls, 0);
    });
  });
}
