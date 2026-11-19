import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '00000000-0000-4000-8289-0000000000aa';
const _admin = '00000000-0000-4000-8289-0000000000bb';

const _ownerPrincipal = AuthenticatedUser(
  userId: UserId(_owner),
  role: PlatformRole.admin,
);

/// The owner seats: [_owner] alone, or a failed read.
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

/// The switches' rows, in memory; the crowning guard reads [on] too.
final class _Rows implements OwnerSwitches, OwnerSwitchSettings {
  bool on = true;
  String? reason;
  UserId? by;
  int writes = 0;

  @override
  Future<Result<bool>> isOn(OwnerSwitch which) async => Result.ok(on);

  @override
  Future<Result<List<OwnerSwitchState>>> all() async => Result.ok([
    OwnerSwitchState(
      which: OwnerSwitch.crowning,
      isOn: on,
      reason: reason,
      changedBy: by,
      changedAt: DateTime.utc(2026, 11, 20),
    ),
  ]);

  @override
  Future<Result<void>> set({
    required OwnerSwitch which,
    required bool on,
    required String reason,
    required UserId by,
  }) async {
    writes++;
    this.on = on;
    this.reason = reason;
    this.by = by;
    return const Result.ok(null);
  }
}

// NK289_15
/// Script 289: the owners' switch board, and the crowning guard reading
/// what it writes.
void main() {
  late _Rows rows;
  late _Seats seats;
  late OwnerSwitchBoard board;

  setUp(() {
    rows = _Rows();
    seats = _Seats();
    board = OwnerSwitchBoard(settings: rows, owners: seats);
  });

  test('an owner turns the crowning off, and the guard holds it', () async {
    final CrowningGuard guard = CrowningGuard(switches: rows, owners: seats);
    const AuthenticatedUser admin = AuthenticatedUser(
      userId: UserId(_admin),
      role: PlatformRole.admin,
    );
    expect(await guard.admitsByHand(admin), isTrue);

    final result = await board.set(
      principal: _ownerPrincipal,
      key: 'crowning',
      on: false,
      reason: '  مراجعة نقاط الشهر ',
    );

    final OwnerSwitchState state = (result as Ok<OwnerSwitchState>).value;
    expect(state.isOn, isFalse);
    expect(state.reason, 'مراجعة نقاط الشهر');
    expect(state.changedBy, const UserId(_owner));
    expect((await guard.isOn() as Ok<bool>).value, isFalse);
    expect(await guard.admitsByHand(admin), isFalse);
    expect(await guard.admitsByHand(_ownerPrincipal), isTrue);
  });

  test('an owner lists the switches', () async {
    final result = await board.list(principal: _ownerPrincipal);

    expect(
      (result as Ok<List<OwnerSwitchState>>).value.single.which,
      OwnerSwitch.crowning,
    );
  });

  test('a reason is required, 200 characters at most', () async {
    for (final String? reason in <String?>[null, '', '   ', 'x' * 201]) {
      final result = await board.set(
        principal: _ownerPrincipal,
        key: 'crowning',
        on: false,
        reason: reason,
      );
      expect(
        (result as Err<OwnerSwitchState>).error.code,
        'owner.reason_required',
      );
    }
    expect(rows.writes, 0);
  });

  test('an unknown switch is refused', () async {
    final result = await board.set(
      principal: _ownerPrincipal,
      key: 'nothing',
      on: false,
      reason: 'x',
    );

    expect(
      (result as Err<OwnerSwitchState>).error.code,
      'owner.switch_unknown',
    );
    expect(rows.writes, 0);
  });

  test('an admin without a seat, a player, a failed seat read', () async {
    const AuthenticatedUser admin = AuthenticatedUser(
      userId: UserId(_admin),
      role: PlatformRole.admin,
    );
    const AuthenticatedUser player = AuthenticatedUser(
      userId: UserId(_owner),
      role: PlatformRole.user,
    );

    Future<String> refused(AuthenticatedUser who) async {
      final result = await board.set(
        principal: who,
        key: 'crowning',
        on: false,
        reason: 'x',
      );
      return (result as Err<OwnerSwitchState>).error.code;
    }

    expect(await refused(admin), 'admin.owner_only');
    expect(await refused(player), isNot('admin.owner_only'));
    seats.fails = true;
    expect(await refused(_ownerPrincipal), 'admin.owner_only');
    expect(
      await board.list(principal: _ownerPrincipal),
      isA<Err<List<OwnerSwitchState>>>(),
    );
    expect(rows.writes, 0);
    expect(rows.on, isTrue);
  });
}
