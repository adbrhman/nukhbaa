import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';
import '../scoring/fake_fixture_score_repository.dart';
import 'fakes.dart';

const _fixture = '33333333-3333-3333-3333-333333333333';
const _p1 = '22222222-2222-2222-2222-222222222222';
const _p2 = '77777777-7777-7777-7777-777777777777';
const _admin = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _e1 = '11111111-1111-1111-1111-111111111111';
const _e2 = '99999999-9999-9999-9999-999999999999';
const _e3 = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _e4 = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

/// Builds a [ParticipantFixtureScore] for [_fixture] (tests arrange scoring
/// state directly, mirroring `ledgerScore` in fakes.dart for the round side).
ParticipantFixtureScore fixtureScore({
  required String participantId,
  required int points,
  FixtureScoreGrade grade = FixtureScoreGrade.exactScoreline,
  int rulesetVersion = 1,
}) =>
    (ParticipantFixtureScore.fromGraded(
              fixture: const FixtureRef(_fixture),
              participantId: ParticipantId(participantId),
              rulesetVersion: rulesetVersion,
              result: FixtureScoreResult(
                fixture: const FixtureRef(_fixture),
                grade: grade,
                points: points,
              ),
            )
            as Ok<ParticipantFixtureScore>)
        .value;

void main() {
  late FakeFixtureScoreRepository scores;
  late FakeFixtureLedgerRepository ledger;
  late FakeIdGenerator ids;
  late PostFixtureToLedger useCase;

  setUp(() {
    scores = FakeFixtureScoreRepository();
    ledger = FakeFixtureLedgerRepository();
    ids = FakeIdGenerator([_e1, _e2, _e3, _e4]);
    useCase = PostFixtureToLedger(
      fixtureScoreRepository: scores,
      fixtureLedgerRepository: ledger,
      idGenerator: ids,
      clock: FixedClock(DateTime.utc(2026, 7, 11, 12)),
    );
  });

  test('أول ترحيل: قيد fixture_score واحد لكل مشارك', () async {
    await scores.saveFixtureScores([
      fixtureScore(participantId: _p1, points: 4),
      fixtureScore(participantId: _p2, points: 1),
    ]);

    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
    );

    expect(r, isA<Ok<List<FixturePointEntry>>>());
    final appended = (r as Ok<List<FixturePointEntry>>).value;
    expect(appended.length, 2);
    expect(ledger.count, 2);
    for (final e in appended) {
      expect(e.kind, EntryKind.fixtureScore);
      expect(e.fixture, const FixtureRef(_fixture));
    }
    final byParticipant = {
      for (final e in appended) e.participantId.value: e.amount,
    };
    expect(byParticipant[_p1], 4);
    expect(byParticipant[_p2], 1);
  });

  test('تصحيح بعد تعديل النتيجة: يُرحّل الفرق فقط كـ correction', () async {
    await scores.saveFixtureScores([
      fixtureScore(participantId: _p1, points: 4),
      fixtureScore(participantId: _p2, points: 1),
    ]);
    await useCase.call(principal: adminPrincipal(_admin), fixtureId: _fixture);
    expect(ledger.count, 2);

    // الأدمن يصحّح نتيجة المباراة؛ RecordFixtureResult + ScoreFixture يعيدان
    // الحساب فعليًا (هنا نحاكيه بإعادة upsert على FakeFixtureScoreRepository،
    // تمامًا كسلوك الـ port الموثّق: يستبدل مكانه، لا يكرّر الصف).
    await scores.saveFixtureScores([
      fixtureScore(participantId: _p1, points: 6), // كان 4، صار 6
    ]);

    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
    );

    expect(r, isA<Ok<List<FixturePointEntry>>>());
    final appended = (r as Ok<List<FixturePointEntry>>).value;
    // فقط p1 تغيّرت نتيجته؛ p2 بلا تغيير فلا قيد جديد له (delta == 0).
    expect(appended.length, 1);
    final correction = appended.single;
    expect(correction.kind, EntryKind.correction);
    expect(correction.participantId, const ParticipantId(_p1));
    expect(correction.amount, 2); // delta = 6 - 4
    expect(ledger.count, 3);

    // مجموع قيود p1 في الليدجر يطابق نتيجته المصحَّحة بعد الفرق.
    final p1Entries =
        (await ledger.listEntries(const ParticipantId(_p1))
                as Ok<List<FixturePointEntry>>)
            .value;
    final p1Total = p1Entries.fold<int>(0, (sum, e) => sum + e.amount);
    expect(p1Total, 6);
  });

  test('إعادة ترحيل بلا تغيير: لا يُرحّل شيء', () async {
    await scores.saveFixtureScores([
      fixtureScore(participantId: _p1, points: 4),
      fixtureScore(participantId: _p2, points: 1),
    ]);
    await useCase.call(principal: adminPrincipal(_admin), fixtureId: _fixture);
    expect(ledger.count, 2);

    final r = await useCase.call(
      principal: adminPrincipal(_admin),
      fixtureId: _fixture,
    );

    expect(r, isA<Ok<List<FixturePointEntry>>>());
    expect((r as Ok<List<FixturePointEntry>>).value, isEmpty);
    expect(ledger.count, 2);
  });
}
