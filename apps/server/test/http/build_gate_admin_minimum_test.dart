/// Script 148: the build gate follows the minimum an admin raises from the
/// dashboard. Wired as the root wires it: one [CachedAppUpdatePolicyStore]
/// behind the admin's [SetMinSupportedBuild] and the gate's
/// [ReadMinSupportedBuild] (through [adminMinimumFrom]); only the database
/// row and the newest release are faked.
library;

import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/http/build_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

RequestContext _context(String path, Map<String, String> headers) {
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.get);
  when(() => request.uri).thenReturn(Uri.parse('https://api.test$path'));
  when(() => request.headers).thenReturn(headers);
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  return context;
}

/// The one row of `ops.app_update_policy`, counting its reads.
final class _PolicyRow implements AppUpdatePolicyStore {
  int? value;
  int reads = 0;

  @override
  Future<Result<int?>> minSupportedBuild() async {
    reads++;
    return Result.ok(value);
  }

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) async {
    value = buildNumber;
    return Result.ok(value);
  }
}

/// The newest published release: build 800.
final class _Releases implements BuildInfoRepository {
  @override
  Future<Result<LatestBuild>> fetchLatest() async => Result.ok(
    LatestBuild(
      publishedAt: DateTime.utc(2026, 10, 26),
      apkUrl: 'https://github.com/x/y/releases/download/build-abc/a.apk',
      buildNumber: 800,
    ),
  );
}

const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('00000000-0000-4000-8000-0000000000ad'),
  role: PlatformRole.admin,
);

/// The root's wiring of the slice, over [row].
({SetMinSupportedBuild setMinimum, Middleware gate}) _wired(
  _PolicyRow row, {
  int? fromEnvironment,
}) {
  final store = CachedAppUpdatePolicyStore(row);
  final read = ReadMinSupportedBuild(store);
  return (
    setMinimum: SetMinSupportedBuild(policy: store, builds: _Releases()),
    gate: buildGate(
      minBuild: fromEnvironment,
      adminMinimum: () => adminMinimumFrom(read.call),
    ),
  );
}

Future<int> _status(
  Middleware gate,
  String path, [
  Map<String, String> headers = const <String, String>{},
]) async {
  final Handler handler = gate((_) => Response(body: 'served'));
  return (await handler(_context(path, headers))).statusCode;
}

void main() {
  test('the admin raising the minimum refuses an older build at once, and '
      'clearing it serves every build again', () async {
    final row = _PolicyRow();
    final slice = _wired(row);

    expect(await _status(slice.gate, '/feed'), HttpStatus.ok);

    await slice.setMinimum(principal: _admin, toLatest: true);
    expect(row.value, 800);
    expect(
      await _status(slice.gate, '/feed', {appBuildHeader: '799'}),
      HttpStatus.conflict,
    );
    expect(await _status(slice.gate, '/feed'), HttpStatus.conflict);
    expect(
      await _status(slice.gate, '/feed', {appBuildHeader: '800'}),
      HttpStatus.ok,
    );

    await slice.setMinimum(principal: _admin, toLatest: false);
    expect(await _status(slice.gate, '/feed'), HttpStatus.ok);
    expect(
      await _status(slice.gate, '/feed', {appBuildHeader: '700'}),
      HttpStatus.ok,
    );
    // The admin's writes were held: the gate read the row once, before them.
    expect(row.reads, 1);
  });

  test('the higher of the variable and the admin minimum applies', () async {
    final row = _PolicyRow()..value = 800;
    final slice = _wired(row, fromEnvironment: 772);

    expect(
      await _status(slice.gate, '/feed', {appBuildHeader: '780'}),
      HttpStatus.conflict,
    );
    expect(servedMinimum(fromEnvironment: 772, fromAdmin: 800), 800);
    expect(servedMinimum(fromEnvironment: 900, fromAdmin: 800), 900);
    expect(servedMinimum(fromEnvironment: 772, fromAdmin: null), 772);
    expect(servedMinimum(fromEnvironment: null, fromAdmin: 800), 800);
    expect(servedMinimum(fromEnvironment: null, fromAdmin: null), isNull);
  });

  test('an unreadable minimum is no minimum: the gate never shuts the service '
      'by mistake', () async {
    final Middleware gate = buildGate(
      minBuild: null,
      adminMinimum: () async => throw StateError('database down'),
    );
    final Middleware failed = buildGate(
      minBuild: null,
      adminMinimum: () => adminMinimumFrom(
        () async => const Result.err(AppError.transient('db.down', 'down')),
      ),
    );

    expect(await _status(gate, '/feed'), HttpStatus.ok);
    expect(await _status(failed, '/feed'), HttpStatus.ok);
  });

  test('the update check, the web build and a local run never read the '
      'minimum', () async {
    final row = _PolicyRow()..value = 800;
    final slice = _wired(row);

    expect(await _status(slice.gate, '/app/latest-build'), HttpStatus.ok);
    expect(
      await _status(slice.gate, '/feed', {'origin': 'https://nukhbaa.app'}),
      HttpStatus.ok,
    );
    expect(
      await _status(slice.gate, '/feed', {appBuildHeader: '0'}),
      HttpStatus.ok,
    );
    expect(row.reads, 0);
  });
}
