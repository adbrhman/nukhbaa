import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/groups/invitees/index.dart' as invitees_route;
import 'competition_route_harness.dart';

// `GET /groups/invitees`: the real route and the real SearchGroupInvitees
// over an in-memory directory.

const _friendUserId = 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1';

final class _Directory implements InviteeDirectory {
  final List<String> queries = <String>[];
  final List<UserId> excluded = <UserId>[];

  @override
  Future<Result<List<GroupInvitee>>> search({
    required String query,
    required UserId excluding,
    required int limit,
  }) async {
    queries.add(query);
    excluded.add(excluding);
    return const Result.ok(<GroupInvitee>[
      GroupInvitee(userId: UserId(_friendUserId), displayName: 'Badr'),
    ]);
  }
}

CompositionRoot _root(_Directory directory) => CompositionRoot.forTesting(
  searchGroupInvitees: SearchGroupInvitees(players: directory),
);

void main() {
  test('answers the players matching the trimmed name', () async {
    final directory = _Directory();
    final response = await invitees_route.onRequest(
      wireContext(
        root: _root(directory),
        principal: userPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'q': '  Bad '},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    final players = body['players']! as List<Object?>;
    final first = players.single! as Map<Object?, Object?>;
    expect(first['user_id'], _friendUserId);
    expect(first['display_name'], 'Badr');
    expect(directory.queries.single, 'Bad');
    expect(directory.excluded.single.value, kUserId);
  });

  test('a short query answers nothing and searches nothing', () async {
    final directory = _Directory();
    final response = await invitees_route.onRequest(
      wireContext(
        root: _root(directory),
        principal: userPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'q': 'B'},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect(body['players'], isEmpty);
    expect(directory.queries, isEmpty);
  });

  test('any other method is 405', () async {
    final response = await invitees_route.onRequest(
      wireContext(root: _root(_Directory()), principal: userPrincipal()),
    );
    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
