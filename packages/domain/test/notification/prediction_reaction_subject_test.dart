import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _fixture = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _actor = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';

FixtureRef _ref() => (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value;

void main() {
  test('a reaction is told once per reacting player per fixture', () {
    final subject = NotificationSubject.predictionReaction(
      fixture: _ref(),
      actorUserId: const UserId(_actor),
    );
    final again = NotificationSubject.predictionReaction(
      fixture: _ref(),
      actorUserId: const UserId(_actor),
    );
    final someoneElse = NotificationSubject.predictionReaction(
      fixture: _ref(),
      actorUserId: const UserId(_other),
    );

    expect(subject.kind, NotificationKind.predictionReaction);
    expect(subject.fixture, _ref());
    expect(subject.actorUserId, const UserId(_actor));
    expect(subject.dedupeRef, 'prediction_reaction:$_fixture:$_actor');
    expect(subject, again);
    expect(subject.dedupeRef == someoneElse.dedupeRef, isFalse);
  });

  test('the kind carries a stable wire token', () {
    expect(
      NotificationKind.predictionReaction.wireValue,
      'prediction_reaction',
    );
    expect(
      (NotificationKind.tryParse('prediction_reaction') as Ok<NotificationKind>)
          .value,
      NotificationKind.predictionReaction,
    );
  });
}
