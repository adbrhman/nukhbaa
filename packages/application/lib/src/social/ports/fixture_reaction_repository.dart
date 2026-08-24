import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

abstract interface class FixtureReactionRepository {
  Future<Result<void>> upsertReaction(FixtureReaction reaction);

  Future<Result<FixtureReaction?>> findReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  );

  Future<Result<List<FixtureReaction>>> listReactionsForFixture(
    GroupId groupId,
    FixtureRef fixture,
  );

  Future<Result<bool>> removeReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  );
}
