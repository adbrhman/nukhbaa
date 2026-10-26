import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart' show principalUser;

const _user = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _target = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  group('SearchGroupInvitees', () {
    test('a short query searches nothing', () async {
      final directory = _Directory();
      final result = await SearchGroupInvitees(players: directory).call(
        principal: principalUser(userId: _user),
        query: ' a ',
      );
      expect((result as Ok<List<GroupInvitee>>).value, isEmpty);
      expect(directory.queries, isEmpty);
    });

    test('searches the trimmed name, never the caller', () async {
      final directory = _Directory();
      final result = await SearchGroupInvitees(players: directory).call(
        principal: principalUser(userId: _user),
        query: '  Bad ',
      );
      expect(
        (result as Ok<List<GroupInvitee>>).value.single.displayName,
        'Badr',
      );
      expect(directory.queries.single, 'Bad');
      expect(directory.excluded.single, const UserId(_user));
      expect(directory.limits.single, SearchGroupInvitees.limit);
    });
  });
}

final class _Directory implements InviteeDirectory {
  final List<String> queries = <String>[];
  final List<UserId> excluded = <UserId>[];
  final List<int> limits = <int>[];

  @override
  Future<Result<List<GroupInvitee>>> search({
    required String query,
    required UserId excluding,
    required int limit,
  }) async {
    queries.add(query);
    excluded.add(excluding);
    limits.add(limit);
    return const Result.ok(<GroupInvitee>[
      GroupInvitee(userId: UserId(_target), displayName: 'Badr'),
    ]);
  }
}
