import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _u1 = 'aaaaaaaa-0000-0000-0000-000000000001';
const _f1 = 'ffffffff-0000-0000-0000-000000000001';
const _f2 = 'ffffffff-0000-0000-0000-000000000002';
const _p1 = 'bbbbbbbb-0000-0000-0000-000000000001';

const _down = Result<Never>.err(AppError.transient('db.down', 'down'));

const _active = User(
  id: UserId(_u1),
  email: 'a@example.com',
  role: PlatformRole.user,
  status: UserStatus.active,
  displayName: 'A',
);

const _suspended = User(
  id: UserId(_u1),
  email: 'a@example.com',
  role: PlatformRole.user,
  status: UserStatus.suspended,
  displayName: 'A',
);

final class _CountingDirectory implements UserDirectory {
  int finds = 0;
  int avatarReads = 0;
  Result<User?> nextUser = const Result.ok(_active);

  @override
  Future<Result<User?>> findUser(UserId id) async {
    finds++;
    return nextUser;
  }

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) async {
    avatarReads++;
    return Result.ok(
      StoredAvatar(
        bytes: const [1, 2, 3],
        mime: 'image/png',
        updatedAt: DateTime.utc(2026, 9, 22),
      ),
    );
  }

  @override
  Future<Result<User>> setAvatar(
    UserId userId,
    List<int> bytes,
    String mime,
  ) async => const Result.ok(_active);

  @override
  Future<Result<User>> clearAvatar(UserId userId) async =>
      const Result.ok(_active);

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async =>
      const Result.ok(_active);

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async => const Result.ok(_active);

  @override
  Future<Result<void>> updateUtcOffsetMinutes(
    UserId userId,
    int minutes,
  ) async => const Result.ok(null);
}

final class _AdminRepository implements UserAdminRepository {
  @override
  Future<Result<User?>> findUserById(UserId id) async =>
      const Result.ok(_active);

  @override
  Future<Result<User>> updateUser(User user) async => Result.ok(user);

  @override
  Future<Result<List<User>>> listUsers({
    String? search,
    required int limit,
  }) async => const Result.ok(<User>[]);
}

final class _CountingScores implements FixtureScoreRepository {
  int reads = 0;
  Result<List<ParticipantFixtureScore>> next = const Result.ok(
    <ParticipantFixtureScore>[],
  );

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    reads++;
    return next;
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listBySeasonFixtures(
    List<FixtureRef> fixtures,
  ) async => const Result.ok(<ParticipantFixtureScore>[]);

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async => const Result.ok(null);
}

final class _CountingTeams implements TeamRepository {
  int reads = 0;

  @override
  Future<Result<List<Team>>> listAll() async {
    reads++;
    return const Result.ok(<Team>[]);
  }
}

final class _CountingSchedules implements FixtureScheduleRepository {
  int batchReads = 0;

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    batchReads++;
    return const Result.ok(<FixtureSchedule>[]);
  }

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async =>
      const Result.ok(null);
}

final class _CountingTallies implements FixturePredictionTallyReader {
  int reads = 0;

  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    reads++;
    return const Result.ok(<FixtureOutcomeTally>[]);
  }
}

void main() {
  late DateTime clock;
  setUp(() => clock = DateTime.utc(2026, 9, 22, 12));

  group('CachedUserDirectory', () {
    late _CountingDirectory inner;
    late CachedUserDirectory directory;

    setUp(() {
      inner = _CountingDirectory();
      directory = CachedUserDirectory(inner, now: () => clock);
    });

    test('a repeat findUser inside the ttl is served from memory', () async {
      await directory.findUser(const UserId(_u1));
      final second = await directory.findUser(const UserId(_u1));
      expect(inner.finds, 1);
      expect((second as Ok<User?>).value?.status, UserStatus.active);
    });

    test('findUser goes back to the database after the ttl', () async {
      await directory.findUser(const UserId(_u1));
      clock = clock.add(const Duration(seconds: 30));
      await directory.findUser(const UserId(_u1));
      expect(inner.finds, 2);
    });

    test('failures and absent users are not cached', () async {
      inner.nextUser = _down;
      await directory.findUser(const UserId(_u1));
      inner.nextUser = const Result.ok(null);
      await directory.findUser(const UserId(_u1));
      await directory.findUser(const UserId(_u1));
      expect(inner.finds, 3);
    });

    test('a suspension through the admin path is seen on the next '
        'request', () async {
      final admin = UserCacheEvictingAdminRepository(
        _AdminRepository(),
        onUserChanged: directory.forget,
      );
      await directory.findUser(const UserId(_u1));
      inner.nextUser = const Result.ok(_suspended);
      await admin.updateUser(_suspended);
      final after = await directory.findUser(const UserId(_u1));
      expect(inner.finds, 2);
      expect((after as Ok<User?>).value?.status, UserStatus.suspended);
    });

    test('a picture is read from the database once, and again after it '
        'changes', () async {
      await directory.readAvatar(const UserId(_u1));
      await directory.readAvatar(const UserId(_u1));
      expect(inner.avatarReads, 1);
      await directory.setAvatar(const UserId(_u1), const [9], 'image/png');
      await directory.readAvatar(const UserId(_u1));
      expect(inner.avatarReads, 2);
    });
  });

  group('CachedFixtureScoreRepository', () {
    late _CountingScores inner;
    late CachedFixtureScoreRepository scores;

    setUp(() {
      inner = _CountingScores();
      scores = CachedFixtureScoreRepository(inner, now: () => clock);
    });

    test('a repeat read of the same fixture is served from memory', () async {
      await scores.listByFixture(const FixtureRef(_f1));
      await scores.listByFixture(const FixtureRef(_f1));
      await scores.listByFixture(const FixtureRef(_f2));
      expect(inner.reads, 2);
    });

    test('saving scores for a fixture drops its cached list', () async {
      await scores.listByFixture(const FixtureRef(_f1));
      await scores.saveFixtureScores(const [
        ParticipantFixtureScore.fromStored(
          fixture: FixtureRef(_f1),
          participantId: ParticipantId(_p1),
          rulesetVersion: 1,
          result: FixtureScoreResult(
            fixture: FixtureRef(_f1),
            grade: FixtureScoreGrade.exactScoreline,
            points: 3,
          ),
        ),
      ]);
      await scores.listByFixture(const FixtureRef(_f1));
      expect(inner.reads, 2);
    });

    test('failures are not cached', () async {
      inner.next = _down;
      await scores.listByFixture(const FixtureRef(_f1));
      inner.next = const Result.ok(<ParticipantFixtureScore>[]);
      await scores.listByFixture(const FixtureRef(_f1));
      expect(inner.reads, 2);
    });
  });

  test('CachedTeamRepository reads the catalog once per ttl', () async {
    final inner = _CountingTeams();
    final teams = CachedTeamRepository(inner, now: () => clock);
    await teams.listAll();
    await teams.listAll();
    expect(inner.reads, 1);
    clock = clock.add(const Duration(minutes: 10));
    await teams.listAll();
    expect(inner.reads, 2);
  });

  test('CachedFixtureScheduleRepository serves a repeated fixture set from '
      'memory and forgets it on a write', () async {
    final inner = _CountingSchedules();
    final schedules = CachedFixtureScheduleRepository(inner, now: () => clock);
    await schedules.findByFixtures(const [FixtureRef(_f1), FixtureRef(_f2)]);
    await schedules.findByFixtures(const [FixtureRef(_f2), FixtureRef(_f1)]);
    expect(inner.batchReads, 1);
    await schedules.upsert(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(_f1),
        homeTeam: 'A',
        awayTeam: 'B',
        kickoffAt: DateTime.utc(2026, 9, 23, 18),
      ),
    );
    await schedules.findByFixtures(const [FixtureRef(_f1), FixtureRef(_f2)]);
    expect(inner.batchReads, 2);
  });

  test('CachedFixturePredictionTallyReader reads each fixture set once per '
      'ttl', () async {
    final inner = _CountingTallies();
    final tallies = CachedFixturePredictionTallyReader(inner, now: () => clock);
    await tallies.tallyByFixtures(const [FixtureRef(_f1)]);
    await tallies.tallyByFixtures(const [FixtureRef(_f1)]);
    expect(inner.reads, 1);
    clock = clock.add(const Duration(seconds: 30));
    await tallies.tallyByFixtures(const [FixtureRef(_f1)]);
    expect(inner.reads, 2);
  });
}
