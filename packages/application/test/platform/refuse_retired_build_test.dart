import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const UserId _retired = UserId('00000000-0149-4000-8149-000000000001');
const UserId _other = UserId('00000000-0149-4000-8149-000000000002');

final class _Policy implements AppUpdatePolicyStore {
  _Policy(this.result);

  Result<int?> result;

  @override
  Future<Result<int?>> minSupportedBuild() async => result;

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) => throw UnimplementedError();
}

final class _Players implements RetiredBuildReader {
  _Players(this.result);

  Result<Set<UserId>> result;
  final List<DateTime> asked = <DateTime>[];

  @override
  Future<Result<Set<UserId>>> playersOnBuildsBefore(DateTime before) async {
    asked.add(before);
    return result;
  }
}

void main() {
  test('with a minimum held, the players on a retired build are refused, '
      'nobody else', () async {
    final players = _Players(Result.ok(<UserId>{_retired}));
    final refuse = RefuseRetiredBuild(
      policy: _Policy(const Result.ok(800)),
      players: players,
    );

    expect(await refuse(_retired), isTrue);
    expect(await refuse(_other), isFalse);
    // Before the head-to-head tab: 10 October 00:00 Riyadh.
    expect(players.asked.first, DateTime.utc(2026, 10, 9, 21));
  });

  test(
    'without a minimum nobody is refused, and the list is not read',
    () async {
      final players = _Players(Result.ok(<UserId>{_retired}));
      final refuse = RefuseRetiredBuild(
        policy: _Policy(const Result.ok(null)),
        players: players,
      );

      expect(await refuse(_retired), isFalse);
      expect(players.asked, isEmpty);
    },
  );

  test('an unreadable minimum or list refuses nobody', () async {
    const down = Result<Never>.err(AppError.transient('db.down', 'down'));
    expect(
      await RefuseRetiredBuild(
        policy: _Policy(down),
        players: _Players(Result.ok(<UserId>{_retired})),
      )(_retired),
      isFalse,
    );
    expect(
      await RefuseRetiredBuild(
        policy: _Policy(const Result.ok(800)),
        players: _Players(down),
      )(_retired),
      isFalse,
    );
  });
}
