import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/badges/index.dart' as route;
import 'competition_route_harness.dart';

/// Answers one record for every user, or fails, and logs who was asked.
final class _FakeReader implements PlayerBadgeReader {
  _FakeReader({this.record = PlayerBadgeRecord.none, this.failWith});

  final PlayerBadgeRecord record;
  final AppError? failWith;
  final List<String> asked = [];

  @override
  Future<Result<PlayerBadgeRecord>> recordOf(UserId userId) async {
    asked.add(userId.value);
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(record);
  }
}

CompositionRoot _rootFor(_FakeReader reader) =>
    CompositionRoot.forTesting(getMyBadges: GetMyBadges(badges: reader));

void main() {
  group('GET /me/badges', () {
    test('returns the whole catalog with progress and grant moments', () async {
      final granted = DateTime.utc(2026, 9, 20, 8);
      final reader = _FakeReader(
        record: PlayerBadgeRecord(
          progress: const BadgeProgress(predictionsPlaced: 7),
          unlockedAt: {BadgeCode.firstPrediction: granted},
        ),
      );

      final response = await route.onRequest(
        wireContext(
          root: _rootFor(reader),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(reader.asked, [kNonMemberUserId]);
      final body = await decodeBody(response);
      expect(body['schema_version'], 1);
      final badges = (body['badges']! as List).cast<Map<Object?, Object?>>();
      expect(
        [for (final b in badges) b['code']],
        [for (final code in BadgeCode.values) code.wireName],
      );
      expect(badges[0], {
        'code': 'first_prediction',
        'current': 1,
        'target': 1,
        'unlocked_at': granted.toIso8601String(),
      });
      expect(badges[1], {
        'code': 'predictions_25',
        'current': 7,
        'target': 25,
        'unlocked_at': null,
      });
    });

    test('a failure is mapped through the error envelope', () async {
      final response = await route.onRequest(
        wireContext(
          root: _rootFor(
            _FakeReader(failWith: const AppError.transient('db.down', 'down')),
          ),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      final body = await decodeBody(response);
      expect(body['code'], 'db.down');
    });

    test('a non-GET method is 405', () async {
      final response = await route.onRequest(
        wireContext(
          root: _rootFor(_FakeReader()),
          principal: nonMemberPrincipal(),
          method: HttpMethod.post,
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
