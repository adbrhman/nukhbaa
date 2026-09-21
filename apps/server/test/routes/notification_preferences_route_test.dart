import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/notification-preferences/index.dart' as route;
import 'competition_route_harness.dart';

/// In-memory stand-in for `notification.notification_preferences`: a map
/// from user id to the stored switch, defaults for anyone absent, or a
/// failure on every call.
final class _MemoryPreferences implements NotificationPreferenceRepository {
  _MemoryPreferences({this.failWith});

  final AppError? failWith;
  final Map<String, bool> stored = {};
  final Map<String, bool> storedPreMatch = {};

  @override
  Future<Result<NotificationPreferences>> preferencesOf(UserId userId) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(
      NotificationPreferences(
        predictionReminder: stored[userId.value] ?? true,
        preMatch: storedPreMatch[userId.value] ?? true,
      ),
    );
  }

  @override
  Future<Result<NotificationPreferences>> save(
    UserId userId,
    NotificationPreferences preferences,
  ) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    stored[userId.value] = preferences.predictionReminder;
    storedPreMatch[userId.value] = preferences.preMatch;
    return Result.ok(preferences);
  }

  @override
  Future<Result<Set<String>>> predictionReminderOptOuts() async => Result.ok({
    for (final entry in stored.entries)
      if (!entry.value) entry.key,
  });
}

CompositionRoot _rootFor(_MemoryPreferences preferences) =>
    CompositionRoot.forTesting(
      getMyNotificationPreferences: GetMyNotificationPreferences(
        preferences: preferences,
      ),
      updateMyNotificationPreferences: UpdateMyNotificationPreferences(
        preferences: preferences,
      ),
    );

Future<Response> _call(
  _MemoryPreferences preferences,
  HttpMethod method, {
  Object? body,
}) => route.onRequest(
  wireContext(
    root: _rootFor(preferences),
    principal: nonMemberPrincipal(),
    method: method,
    body: body,
  ),
);

void main() {
  group('GET /me/notification-preferences', () {
    test('a caller who never changed anything reads the defaults', () async {
      final response = await _call(_MemoryPreferences(), HttpMethod.get);

      expect(response.statusCode, HttpStatus.ok);
      expect(await decodeBody(response), {
        'schema_version': 1,
        'prediction_reminder': true,
        'pre_match': true,
      });
    });

    test('reads the stored switch of the caller only', () async {
      final preferences = _MemoryPreferences()
        ..stored[kNonMemberUserId] = false
        ..stored['aaaaaaaa-0000-0000-0000-000000000001'] = true;

      final response = await _call(preferences, HttpMethod.get);

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['prediction_reminder'], false);
    });

    test('a failure is mapped through the error envelope', () async {
      final response = await _call(
        _MemoryPreferences(
          failWith: const AppError.transient('db.down', 'down'),
        ),
        HttpMethod.get,
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect((await decodeBody(response))['code'], 'db.down');
    });
  });

  group('PUT /me/notification-preferences', () {
    test('turning the reminder off is stored for the caller', () async {
      final preferences = _MemoryPreferences();

      final response = await _call(
        preferences,
        HttpMethod.put,
        body: {'prediction_reminder': false},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(await decodeBody(response), {
        'schema_version': 1,
        'prediction_reminder': false,
        'pre_match': true,
      });
      expect(preferences.stored, {kNonMemberUserId: false});

      final reread = await _call(preferences, HttpMethod.get);
      expect((await decodeBody(reread))['prediction_reminder'], false);
    });

    test('pre_match alone is stored and the reminder is kept', () async {
      final preferences = _MemoryPreferences()
        ..stored[kNonMemberUserId] = false;

      final response = await _call(
        preferences,
        HttpMethod.put,
        body: {'pre_match': false},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(await decodeBody(response), {
        'schema_version': 1,
        'prediction_reminder': false,
        'pre_match': false,
      });
      expect(preferences.storedPreMatch, {kNonMemberUserId: false});
    });

    test('turning it back on is stored too', () async {
      final preferences = _MemoryPreferences()
        ..stored[kNonMemberUserId] = false;

      final response = await _call(
        preferences,
        HttpMethod.put,
        body: {'prediction_reminder': true},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(preferences.stored, {kNonMemberUserId: true});
    });

    test('a missing or non-boolean switch is 400 and stores nothing', () async {
      final preferences = _MemoryPreferences();

      final missing = await _call(
        preferences,
        HttpMethod.put,
        body: <String, Object?>{},
      );
      final wrong = await _call(
        preferences,
        HttpMethod.put,
        body: {'prediction_reminder': 'false'},
      );

      expect(missing.statusCode, HttpStatus.badRequest);
      expect(wrong.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(wrong))['code'], 'request.field_missing');
      expect(preferences.stored, isEmpty);
    });

    test('a failure is mapped through the error envelope', () async {
      final response = await _call(
        _MemoryPreferences(
          failWith: const AppError.transient('db.down', 'down'),
        ),
        HttpMethod.put,
        body: {'prediction_reminder': false},
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });
  });

  test('any other method is 405', () async {
    final response = await _call(_MemoryPreferences(), HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
