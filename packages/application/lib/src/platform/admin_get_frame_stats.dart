/// Use-case: the admin's view of frame smoothness (migration 0070).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/platform/ports/frame_report_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Frame totals over the last [windowDays] days: [overall] for every build,
/// and [builds] for the newest few, newest first.
final class FrameStats {
  /// Creates the stats.
  const FrameStats({
    required this.windowDays,
    required this.overall,
    required this.builds,
    this.devices = const <DeviceTotals>[],
  });

  /// The window's length in days.
  final int windowDays;

  /// Every build together.
  final FrameTotals overall;

  /// One entry per build, newest first.
  final List<FrameTotals> builds;

  /// The least smooth device models, each reported by several players.
  final List<DeviceTotals> devices;
}

/// Reads the frame totals for the admin dashboard. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminGetFrameStats {
  /// Creates the use-case over its collaborators.
  const AdminGetFrameStats({
    required FrameReportRepository reports,
    required Clock clock,
  }) : _reports = reports,
       _clock = clock;

  final FrameReportRepository _reports;
  final Clock _clock;

  /// The window when none (or a nonsense one) is asked for.
  static const int defaultDays = 7;

  /// The longest window a read may scan.
  static const int maxDays = 30;

  /// How many builds are broken out.
  static const int maxBuilds = 5;

  /// How many device models are listed.
  static const int maxDevices = 5;

  /// The fewest distinct players a device model needs before it is listed.
  static const int minUsersPerDevice = 3;

  /// Reads the totals of the last [days] days (clamped to 1..[maxDays]).
  Future<Result<FrameStats>> call({
    required AuthenticatedUser principal,
    int? days,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final int window = days == null || days < 1
        ? defaultDays
        : (days > maxDays ? maxDays : days);
    final DateTime since = _clock.nowUtc().subtract(Duration(days: window));
    final result = await _reports.totals(since: since, maxBuilds: maxBuilds);
    final deviceResult = await _reports.devices(
      since: since,
      minUsers: minUsersPerDevice,
      limit: maxDevices,
    );
    // The device list is extra: a failed read of it costs only that list.
    final List<DeviceTotals> devices = switch (deviceResult) {
      Ok<List<DeviceTotals>>(:final value) => value,
      Err<List<DeviceTotals>>() => const <DeviceTotals>[],
    };
    return switch (result) {
      Err<List<FrameTotals>>(:final error) => Result.err(error),
      Ok<List<FrameTotals>>(:final value) => Result.ok(
        FrameStats(
          windowDays: window,
          overall: value.isNotEmpty && value.first.build == null
              ? value.first
              : const FrameTotals(
                  build: null,
                  reports: 0,
                  users: 0,
                  frames: 0,
                  slowFrames: 0,
                  frozenFrames: 0,
                  worstFrameMs: 0,
                  lastReportedAt: null,
                ),
          builds: <FrameTotals>[
            for (final FrameTotals t in value)
              if (t.build != null) t,
          ],
          devices: devices,
        ),
      ),
    };
  }
}
