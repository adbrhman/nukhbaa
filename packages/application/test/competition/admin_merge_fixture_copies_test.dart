/// Script 95 through the real use-cases: an admin previews and merges a
/// copy of a match into the copy kept, and the kept copy is scored again
/// through the official path when something moved and its result is in.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart' show adminPrincipal, userPrincipal;

const _copy = 'fde6264d-0000-4000-8000-000000000001';
const _kept = 'a2e41db8-0000-4000-8000-000000000001';
const _adminId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _playerId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

/// Answers [report] (or [error]) and records every call.
final class _Merger implements FixtureMerger {
  _Merger({this.report = _threeMoved, this.error});

  final FixtureMergeReport report;
  final AppError? error;
  final List<({String duplicate, String kept, String actor, bool apply})>
  calls = [];
  final List<String> copiesAsked = [];

  @override
  Future<Result<FixtureMergeReport>> merge({
    required FixtureRef duplicate,
    required FixtureRef kept,
    required UserId actor,
    required bool apply,
  }) async {
    calls.add((
      duplicate: duplicate.value,
      kept: kept.value,
      actor: actor.value,
      apply: apply,
    ));
    final e = error;
    return e == null ? Result.ok(report) : Result.err(e);
  }

  @override
  Future<Result<List<FixtureCopy>>> copiesOf(FixtureRef fixture) async {
    copiesAsked.add(fixture.value);
    return Result.ok([
      FixtureCopy(
        fixture: fixture,
        homeTeam: 'سالزبورغ',
        awayTeam: 'ميلان',
        kickoffAt: DateTime.utc(2026, 10, 15, 19),
        hidden: true,
        predictions: 3,
        doubles: 0,
        hasResult: false,
        linked: false,
        isSelf: true,
      ),
    ]);
  }
}

const _threeMoved = FixtureMergeReport(
  moved: 3,
  doublesMoved: 0,
  doublesDropped: 0,
  bothPredicted: 1,
  late: 0,
  notParticipant: 0,
  linkMoved: false,
  keptHasResult: true,
);

/// Records the fixtures scored again; fails when [fail].
final class _Rescorer {
  _Rescorer({this.fail = false});

  final bool fail;
  final List<String> fixtures = [];

  Future<Result<void>> call({required String fixtureId}) async {
    fixtures.add(fixtureId);
    return fail
        ? const Result.err(AppError.transient('db.timeout', 'timed out'))
        : const Result.ok(null);
  }
}

void main() {
  group('AdminMergeFixtureCopies', () {
    test('a preview writes nothing and scores nothing', () async {
      final merger = _Merger();
      final rescorer = _Rescorer();
      final result =
          await AdminMergeFixtureCopies(merger: merger, rescore: rescorer.call)(
            principal: adminPrincipal(_adminId),
            duplicateId: _copy,
            keptId: _kept,
            apply: false,
          );

      final report = (result as Ok<FixtureMergeReport>).value;
      expect(report.moved, 3);
      expect(report.applied, isFalse);
      expect(merger.calls.single.apply, isFalse);
      expect(merger.calls.single.actor, _adminId);
      expect(rescorer.fixtures, isEmpty);
    });

    test('a merge into a copy with its result scores the kept copy '
        'again', () async {
      final merger = _Merger();
      final rescorer = _Rescorer();
      final result =
          await AdminMergeFixtureCopies(merger: merger, rescore: rescorer.call)(
            principal: adminPrincipal(_adminId),
            duplicateId: _copy,
            keptId: _kept,
            apply: true,
          );

      final report = (result as Ok<FixtureMergeReport>).value;
      expect(report.applied, isTrue);
      expect(report.rescored, isTrue);
      expect(merger.calls.single.duplicate, _copy);
      expect(merger.calls.single.kept, _kept);
      expect(rescorer.fixtures, [_kept]);
    });

    test('nothing moved: nothing to score again', () async {
      final rescorer = _Rescorer();
      final result =
          await AdminMergeFixtureCopies(
            merger: _Merger(
              report: const FixtureMergeReport(
                moved: 0,
                doublesMoved: 0,
                doublesDropped: 0,
                bothPredicted: 2,
                late: 0,
                notParticipant: 0,
                linkMoved: false,
                keptHasResult: true,
              ),
            ),
            rescore: rescorer.call,
          )(
            principal: adminPrincipal(_adminId),
            duplicateId: _copy,
            keptId: _kept,
            apply: true,
          );

      expect((result as Ok<FixtureMergeReport>).value.rescored, isFalse);
      expect(rescorer.fixtures, isEmpty);
    });

    test('a failed rescore keeps the merge and says so', () async {
      final rescorer = _Rescorer(fail: true);
      final result =
          await AdminMergeFixtureCopies(
            merger: _Merger(),
            rescore: rescorer.call,
          )(
            principal: adminPrincipal(_adminId),
            duplicateId: _copy,
            keptId: _kept,
            apply: true,
          );

      final report = (result as Ok<FixtureMergeReport>).value;
      expect(report.applied, isTrue);
      expect(report.rescored, isFalse);
      expect(rescorer.fixtures, [_kept]);
    });

    test('a refusal of the merge comes back as it is', () async {
      final result =
          await AdminMergeFixtureCopies(
            merger: _Merger(
              error: const AppError.invariant(
                'competition.fixture_merge_refused',
                'دُمجت هذه النسخة من قبل.',
              ),
            ),
          )(
            principal: adminPrincipal(_adminId),
            duplicateId: _copy,
            keptId: _kept,
            apply: true,
          );

      final AppError error = (result as Err<FixtureMergeReport>).error;
      expect(error.kind, ErrorKind.invariant);
      expect(error.message, 'دُمجت هذه النسخة من قبل.');
    });

    test('no copy to keep is refused in Arabic before anything', () async {
      final merger = _Merger();
      final result = await AdminMergeFixtureCopies(merger: merger)(
        principal: adminPrincipal(_adminId),
        duplicateId: _copy,
        keptId: null,
        apply: true,
      );

      final AppError error = (result as Err<FixtureMergeReport>).error;
      expect(error.code, 'competition.fixture_merge_into_invalid');
      expect(error.kind, ErrorKind.validation);
      expect(merger.calls, isEmpty);
    });

    test('a player is refused', () async {
      final merger = _Merger();
      final result = await AdminMergeFixtureCopies(merger: merger)(
        principal: userPrincipal(_playerId),
        duplicateId: _copy,
        keptId: _kept,
        apply: true,
      );

      expect(result, isA<Err<FixtureMergeReport>>());
      expect(merger.calls, isEmpty);
    });
  });

  group('AdminListFixtureCopies', () {
    test('an admin reads the copies of a match', () async {
      final merger = _Merger();
      final result = await AdminListFixtureCopies(merger: merger)(
        principal: adminPrincipal(_adminId),
        fixtureId: _copy,
      );

      final List<FixtureCopy> copies = (result as Ok<List<FixtureCopy>>).value;
      expect(copies.single.isSelf, isTrue);
      expect(copies.single.predictions, 3);
      expect(merger.copiesAsked, [_copy]);
    });

    test('a player is refused, nothing read', () async {
      final merger = _Merger();
      final result = await AdminListFixtureCopies(merger: merger)(
        principal: userPrincipal(_playerId),
        fixtureId: _copy,
      );

      expect(result, isA<Err<List<FixtureCopy>>>());
      expect(merger.copiesAsked, isEmpty);
    });
  });
}
