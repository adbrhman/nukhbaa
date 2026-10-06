import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';

final class _FixedClock implements Clock {
  const _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowUtc() => now;
}

final class _FakeViews implements ScreenViewRepository {
  final List<(String, DateTime, Map<String, int>, DateTime)> calls = [];

  AppError? failWith;

  @override
  Future<Result<void>> add({
    required UserId userId,
    required DateTime day,
    required Map<String, int> opens,
    required DateTime reportedAt,
  }) async {
    final AppError? error = failWith;
    if (error != null) return Result.err(error);
    calls.add((userId.value, day, opens, reportedAt));
    return const Result.ok(null);
  }
}

const _principal = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
  email: 'a@example.com',
  displayName: 'Human',
);

void main() {
  // 22:30 UTC on 6 October is already 7 October in Riyadh.
  final now = DateTime.utc(2026, 10, 6, 22, 30);

  RecordScreenViews useCase(_FakeViews views) =>
      RecordScreenViews(views: views, clock: _FixedClock(now));

  test('known screens are added to the Riyadh day of the report', () async {
    final views = _FakeViews();

    final result = await useCase(views)(
      principal: _principal,
      opens: {ScreenName.duels: 2, ScreenName.home: 5},
    );

    expect((result as Ok<int>).value, 2);
    final call = views.calls.single;
    expect(call.$1, _user);
    expect(call.$2, DateTime.utc(2026, 10, 7));
    expect(call.$3, {'duels': 2, 'home': 5});
    expect(call.$4, now);
  });

  test('an unknown name is dropped and the rest is kept', () async {
    final views = _FakeViews();

    final result = await useCase(views)(
      principal: _principal,
      opens: {'a_screen_from_the_future': 3, ScreenName.badges: 1},
    );

    expect((result as Ok<int>).value, 1);
    expect(views.calls.single.$3, {'badges': 1});
  });

  test('a report of only unknown names writes nothing', () async {
    final views = _FakeViews();

    final result = await useCase(views)(
      principal: _principal,
      opens: {'elsewhere': 1},
    );

    expect((result as Ok<int>).value, 0);
    expect(views.calls, isEmpty);
  });

  test('a count that cannot be true refuses the whole report', () async {
    final views = _FakeViews();

    final zero = await useCase(views)(
      principal: _principal,
      opens: {ScreenName.home: 0},
    );
    final huge = await useCase(views)(
      principal: _principal,
      opens: {ScreenName.home: RecordScreenViews.maxOpensPerScreen + 1},
    );

    expect((zero as Err<int>).error.code, 'screen_views.invalid_count');
    expect((huge as Err<int>).error.code, 'screen_views.invalid_count');
    expect(views.calls, isEmpty);
  });

  test('more screens than any app has is refused', () async {
    final views = _FakeViews();

    final result = await useCase(views)(
      principal: _principal,
      opens: {
        for (var i = 0; i <= RecordScreenViews.maxScreens; i++) 'screen_$i': 1,
      },
    );

    expect((result as Err<int>).error.code, 'screen_views.too_many');
    expect(views.calls, isEmpty);
  });

  test('a storage failure is returned, not thrown', () async {
    final views = _FakeViews()
      ..failWith = const AppError.transient('db.down', 'down');

    final result = await useCase(views)(
      principal: _principal,
      opens: {ScreenName.home: 1},
    );

    expect((result as Err<int>).error.code, 'db.down');
  });

  test('every screen name has the shape the table accepts', () {
    final shape = RegExp(r'^[a-z][a-z0-9_]{1,39}$');
    for (final name in ScreenName.all) {
      expect(shape.hasMatch(name), isTrue, reason: name);
    }
  });
}
