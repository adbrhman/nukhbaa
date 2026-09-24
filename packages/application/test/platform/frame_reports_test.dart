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

final class _FakeReports implements FrameReportRepository {
  final List<(String, FrameReport, DateTime)> kept = [];
  DateTime? since;
  int? maxBuilds;
  List<FrameTotals> answer = const [];

  @override
  Future<Result<void>> record({
    required UserId userId,
    required FrameReport report,
    required DateTime reportedAt,
  }) async {
    kept.add((userId.value, report, reportedAt));
    return const Result.ok(null);
  }

  @override
  Future<Result<List<FrameTotals>>> totals({
    required DateTime since,
    required int maxBuilds,
  }) async {
    this.since = since;
    this.maxBuilds = maxBuilds;
    return Result.ok(answer);
  }
}

const _player = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);
const _admin = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.admin,
);

FrameReport _report({
  String build = 'abc1234',
  String platform = 'android',
  int hz = 120,
  int frames = 1000,
  int slow = 30,
  int frozen = 1,
  int worst = 900,
}) => FrameReport(
  build: build,
  platform: platform,
  refreshRateHz: hz,
  frames: frames,
  slowFrames: slow,
  frozenFrames: frozen,
  worstFrameMs: worst,
);

FrameTotals _totals(String? build, int frames) => FrameTotals(
  build: build,
  reports: 2,
  users: 1,
  frames: frames,
  slowFrames: 10,
  frozenFrames: 0,
  worstFrameMs: 40,
  lastReportedAt: DateTime.utc(2026, 9, 24),
);

void main() {
  final now = DateTime.utc(2026, 9, 24, 12);

  group('RecordFrameReport', () {
    test('a sound report is kept against the caller', () async {
      final reports = _FakeReports();

      final result = await RecordFrameReport(
        reports: reports,
        clock: _FixedClock(now),
      )(principal: _player, report: _report());

      expect(result.isOk, isTrue);
      expect(reports.kept.single.$1, _user);
      expect(reports.kept.single.$2.frames, 1000);
      expect(reports.kept.single.$3, now);
    });

    test('a report that cannot be true is refused, nothing kept', () async {
      final reports = _FakeReports();
      final use = RecordFrameReport(reports: reports, clock: _FixedClock(now));

      for (final bad in <FrameReport>[
        _report(slow: 1001),
        _report(frozen: 31),
        _report(frames: 0, slow: 0, frozen: 0),
        _report(hz: 0),
        _report(hz: 1000),
        _report(platform: 'desktop'),
        _report(build: ''),
        _report(build: 'x' * 41),
        _report(build: 'drop table'),
        _report(worst: -1),
      ]) {
        final result = await use(principal: _player, report: bad);
        expect(result.isErr, isTrue);
        expect((result as Err<void>).error.code, 'perf.invalid_report');
      }
      expect(reports.kept, isEmpty);
    });
  });

  group('AdminGetFrameStats', () {
    test('splits the overall row from the builds, default week', () async {
      final reports = _FakeReports()
        ..answer = [
          _totals(null, 5000),
          _totals('new1234', 3000),
          _totals('old1234', 2000),
        ];

      final result = await AdminGetFrameStats(
        reports: reports,
        clock: _FixedClock(now),
      )(principal: _admin);

      final stats = (result as Ok<FrameStats>).value;
      expect(stats.windowDays, AdminGetFrameStats.defaultDays);
      expect(stats.overall.frames, 5000);
      expect(stats.builds.map((b) => b.build), ['new1234', 'old1234']);
      expect(reports.since, now.subtract(const Duration(days: 7)));
      expect(reports.maxBuilds, AdminGetFrameStats.maxBuilds);
    });

    test('clamps the window and survives an empty table', () async {
      final reports = _FakeReports();
      final use = AdminGetFrameStats(reports: reports, clock: _FixedClock(now));

      final long = await use(principal: _admin, days: 400);
      expect((long as Ok<FrameStats>).value.windowDays, 30);
      expect(long.value.overall.frames, 0);
      expect(long.value.builds, isEmpty);

      final zero = await use(principal: _admin, days: 0);
      expect((zero as Ok<FrameStats>).value.windowDays, 7);
    });

    test('a player is refused', () async {
      final result = await AdminGetFrameStats(
        reports: _FakeReports(),
        clock: _FixedClock(now),
      )(principal: _player);

      expect((result as Err<FrameStats>).error.code, 'auth.insufficient_role');
    });
  });
}
