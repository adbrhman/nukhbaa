import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/owner_switch_stop.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/chat/index.dart' as chat;
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/[fixtureId]/prediction/index.dart'
    as prediction;
import 'competition_route_harness.dart';

/// The owners' switches in memory: [off] holds those turned off.
final class _Switches implements OwnerSwitches {
  final Set<OwnerSwitch> off = <OwnerSwitch>{};
  bool fails = false;
  int reads = 0;

  @override
  Future<Result<bool>> isOn(OwnerSwitch which) async {
    reads++;
    if (fails) return const Result.err(AppError.transient('db.down', 'down'));
    return Result.ok(!off.contains(which));
  }
}

// NK291_07
/// Script 291: the owners' stops on the predictions and the chat, through
/// the real routes. The use-cases behind them are the composition root's
/// unwired ones, which throw if reached: a refused write never gets there.
void main() {
  late _Switches switches;
  late CompositionRoot root;

  setUp(() {
    switches = _Switches();
    root = CompositionRoot.forTesting(ownerSwitches: switches);
  });

  test('predictions off: a prediction is refused before anything', () async {
    switches.off.add(OwnerSwitch.predictions);

    final Response response = await prediction.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        body: const {'home_goals': 1, 'away_goals': 0},
      ),
      'season-1',
      'fixture-1',
    );

    expect(response.statusCode, HttpStatus.conflict);
    final Map<String, Object?> body = await decodeBody(response);
    expect(body['code'], 'prediction.paused');
    expect(body['message'], contains('متوقف مؤقتاً'));
  });

  test('chat off: a message is refused, admins too', () async {
    switches.off.add(OwnerSwitch.chat);

    final Response response = await chat.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        body: const {'body': 'مرحبا'},
      ),
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect((await decodeBody(response))['code'], 'h2h.chat_paused');
  });

  test('a switch is read on every request, and on serves it', () async {
    expect(await ownerSwitchStop(root, OwnerSwitch.predictions), isNull);
    switches.off.add(OwnerSwitch.predictions);
    expect(await ownerSwitchStop(root, OwnerSwitch.predictions), isNotNull);
    expect(await ownerSwitchStop(root, OwnerSwitch.chat), isNull);
    expect(switches.reads, 3, reason: 'nothing is cached');
  });

  test('a switch that cannot be read refuses with the failure', () async {
    switches.fails = true;

    final Response? refused = await ownerSwitchStop(
      root,
      OwnerSwitch.predictions,
    );

    expect(refused!.statusCode, HttpStatus.serviceUnavailable);
  });

  test('no switches wired serves every write', () async {
    expect(
      await ownerSwitchStop(
        CompositionRoot.forTesting(),
        OwnerSwitch.predictions,
      ),
      isNull,
    );
  });
}
