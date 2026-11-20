import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '00000000-0000-4000-8292-0000000000aa';

final class _Seats implements OwnerNotices {
  bool fails = false;

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<bool>> isOwner(UserId user) async => fails
      ? const Result.err(AppError.transient('db.down', 'down'))
      : Result.ok(user == const UserId(_owner));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Store implements AppModeStore {
  AppMode mode = AppMode.normal;
  String? reason;
  UserId? by;
  int writes = 0;

  @override
  Future<Result<AppModeState>> read() async => Result.ok(
    AppModeState(
      mode: mode,
      reason: reason,
      changedBy: by,
      changedAt: DateTime.utc(2026, 11, 20),
    ),
  );

  @override
  Future<Result<void>> set({
    required AppMode mode,
    required String reason,
    required UserId by,
  }) async {
    writes++;
    this.mode = mode;
    this.reason = reason;
    this.by = by;
    return const Result.ok(null);
  }
}

// NK292_13
/// Script 292: the owners' hand on the app's mode.
void main() {
  late _Store store;
  late _Seats seats;
  late OwnerAppMode modes;
  const AuthenticatedUser owner = AuthenticatedUser(
    userId: UserId(_owner),
    role: PlatformRole.admin,
  );

  setUp(() {
    store = _Store();
    seats = _Seats();
    modes = OwnerAppMode(store: store, owners: seats);
  });

  test('an owner sets read only for a reason', () async {
    final result = await modes.set(
      principal: owner,
      wire: 'read_only',
      reason: ' خطأ في النقاط ',
    );

    final AppModeState state = (result as Ok<AppModeState>).value;
    expect(state.mode, AppMode.readOnly);
    expect(state.reason, 'خطأ في النقاط');
    expect(state.changedBy, const UserId(_owner));
  });

  test('an unknown mode or no reason writes nothing', () async {
    final unknown = await modes.set(principal: owner, wire: 'off', reason: 'x');
    final blank = await modes.set(
      principal: owner,
      wire: 'closed',
      reason: ' ',
    );

    expect((unknown as Err<AppModeState>).error.code, 'owner.mode_unknown');
    expect((blank as Err<AppModeState>).error.code, 'owner.reason_required');
    expect(store.writes, 0);
  });

  test('another admin, a player, a failed seat read: refused', () async {
    const AuthenticatedUser admin = AuthenticatedUser(
      userId: UserId('00000000-0000-4000-8292-0000000000bb'),
      role: PlatformRole.admin,
    );
    const AuthenticatedUser player = AuthenticatedUser(
      userId: UserId(_owner),
      role: PlatformRole.user,
    );

    final refusedAdmin = await modes.set(
      principal: admin,
      wire: 'closed',
      reason: 'x',
    );
    final refusedPlayer = await modes.state(principal: player);
    seats.fails = true;
    final refusedOwner = await modes.state(principal: owner);

    expect((refusedAdmin as Err<AppModeState>).error.code, 'admin.owner_only');
    expect(refusedPlayer, isA<Err<AppModeState>>());
    expect((refusedOwner as Err<AppModeState>).error.code, 'admin.owner_only');
    expect(store.writes, 0);
  });
}
