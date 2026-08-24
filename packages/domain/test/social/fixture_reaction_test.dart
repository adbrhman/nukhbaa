import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('FixtureReaction.create', () {
    test('creates a valid reaction', () {
      final emoji = ReactionEmoji.tryParse('fire') as Ok<ReactionEmoji>;
      final result = FixtureReaction.create(
        id: const ReactionId('11111111-1111-1111-1111-111111111111'),
        groupId: const GroupId('22222222-2222-2222-2222-222222222222'),
        fixture: const FixtureRef('33333333-3333-3333-3333-333333333333'),
        userId: const UserId('44444444-4444-4444-4444-444444444444'),
        emoji: emoji.value,
        reactedAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<FixtureReaction>>());
    });

    test('rejects a non-UTC reactedAt', () {
      final emoji = ReactionEmoji.tryParse('fire') as Ok<ReactionEmoji>;
      final result = FixtureReaction.create(
        id: const ReactionId('11111111-1111-1111-1111-111111111111'),
        groupId: const GroupId('22222222-2222-2222-2222-222222222222'),
        fixture: const FixtureRef('33333333-3333-3333-3333-333333333333'),
        userId: const UserId('44444444-4444-4444-4444-444444444444'),
        emoji: emoji.value,
        reactedAt: DateTime(2026, 8, 1),
      );
      expect(result, isA<Err<FixtureReaction>>());
    });
  });

  group('FixtureReaction.changeEmoji', () {
    test('preserves identity while swapping the emoji', () {
      final first = ReactionEmoji.tryParse('fire') as Ok<ReactionEmoji>;
      final second = ReactionEmoji.tryParse('laugh') as Ok<ReactionEmoji>;
      final created =
          FixtureReaction.create(
                id: const ReactionId('11111111-1111-1111-1111-111111111111'),
                groupId: const GroupId('22222222-2222-2222-2222-222222222222'),
                fixture: const FixtureRef(
                  '33333333-3333-3333-3333-333333333333',
                ),
                userId: const UserId('44444444-4444-4444-4444-444444444444'),
                emoji: first.value,
                reactedAt: DateTime.utc(2026, 8, 1),
              )
              as Ok<FixtureReaction>;

      final changed = created.value.changeEmoji(
        second.value,
        DateTime.utc(2026, 8, 2),
      );

      expect(changed, isA<Ok<FixtureReaction>>());
      final value = (changed as Ok<FixtureReaction>).value;
      expect(value.id, created.value.id);
      expect(value.fixture, created.value.fixture);
      expect(value.emoji, second.value);
    });
  });
}
