import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/launch_invite.dart';

/// The league and duel links players share carry their code in the address
/// the web build opens with; anything else is ignored.
void main() {
  test('a league link carries its code', () {
    final invite = launchInviteFrom(
      Uri.parse('https://adbrhman.github.io/nukhbaa/?league=abcd23efgh'),
    );
    expect(invite.league, 'ABCD23EFGH');
    expect(invite.duel, isNull);
  });

  test('a duel link carries its code', () {
    final invite = launchInviteFrom(
      Uri.parse('https://x.example/nukhbaa/?duel=WHAVVHPE9D48#/'),
    );
    expect(invite.duel, 'WHAVVHPE9D48');
    expect(invite.league, isNull);
  });

  test('no code, or a malformed one, is nothing', () {
    expect(
      launchInviteFrom(Uri.parse('https://x.example/nukhbaa/')).league,
      isNull,
    );
    expect(
      launchInviteFrom(Uri.parse('https://x.example/?league=<script>')).league,
      isNull,
    );
  });
}
