import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const UserId _retired = UserId('00000000-0149-4000-8149-000000000001');
const UserId _other = UserId('00000000-0149-4000-8149-000000000002');

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
  test('switched on, the players on a retired build are refused, nobody '
      'else', () async {
    final players = _Players(Result.ok(<UserId>{_retired}));
    final refuse = RefuseRetiredBuild(enabled: true, players: players);

    expect(await refuse(_retired), isTrue);
    expect(await refuse(_other), isFalse);
    // Before the head-to-head tab: 10 October 00:00 Riyadh.
    expect(players.asked.first, DateTime.utc(2026, 10, 9, 21));
  });

  test('switched off, nobody is refused, and the list is not read', () async {
    final players = _Players(Result.ok(<UserId>{_retired}));
    final refuse = RefuseRetiredBuild(enabled: false, players: players);

    expect(await refuse(_retired), isFalse);
    expect(players.asked, isEmpty);
  });

  test('an unreadable list refuses nobody', () async {
    final refuse = RefuseRetiredBuild(
      enabled: true,
      players: _Players(
        const Result.err(AppError.transient('db.down', 'down')),
      ),
    );

    expect(await refuse(_retired), isFalse);
  });

  test('the switch reads on, true, yes or 1; anything else is off', () {
    for (final raw in <String>['on', 'ON', ' true ', 'yes', '1']) {
      expect(RefuseRetiredBuild.switchedOn(raw), isTrue, reason: raw);
    }
    for (final raw in <String?>[null, '', 'off', '0', 'no', 'soon']) {
      expect(RefuseRetiredBuild.switchedOn(raw), isFalse, reason: raw);
    }
  });
}
