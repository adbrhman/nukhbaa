import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/notifications/push_link.dart';

void main() {
  group('shellTabForLink', () {
    test('each known link opens its tab', () {
      expect(shellTabForLink(PushLinks.fixtures), 1);
      expect(shellTabForLink(PushLinks.league), 3);
      expect(shellTabForLink(PushLinks.inbox), 0);
    });

    test('a duel push opens the home tab and carries its code', () {
      expect(shellTabForLink(PushLinks.duel), 0);
      expect(shellTabForLink('duel:ABCDEFGHJKMN'), 0);
      expect(duelCodeForLink('duel:ABCDEFGHJKMN'), 'ABCDEFGHJKMN');
      expect(duelCodeForLink(PushLinks.duel), isNull);
      expect(duelCodeForLink('duel:'), isNull);
      expect(pushOpenNameForLink('duel:ABCDEFGHJKMN'), PushLinks.duel);
      expect(pushOpenNameForLink(PushLinks.inbox), PushLinks.inbox);
    });

    test('an unknown link opens nothing in particular', () {
      expect(shellTabForLink('something-newer'), isNull);
    });

    test('the names match what the server sends', () {
      expect(PushLinks.fixtures, 'fixtures');
      expect(PushLinks.league, 'league');
      expect(PushLinks.inbox, 'inbox');
      expect(PushLinks.duel, 'duel');
    });
  });
}
