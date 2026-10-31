import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/notifications/push_link.dart';

void main() {
  group('shellTabForLink', () {
    test('each known link opens its tab', () {
      expect(shellTabForLink(PushLinks.fixtures), 1);
      expect(shellTabForLink(PushLinks.league), 3);
      expect(shellTabForLink(PushLinks.inbox), 0);
      // Support answered: the chat over the account tab (script 166).
      expect(shellTabForLink(PushLinks.support), 4);
      // A player wrote: the admins' inbox over the account tab (167).
      expect(shellTabForLink(PushLinks.supportInbox), 4);
      // An absence warning, a relegation or a promotion: the league's tab.
      expect(shellTabForLink(PushLinks.h2h), 2);
    });

    test('an unknown link opens nothing in particular', () {
      expect(shellTabForLink('something-newer'), isNull);
      // The duels were removed (2026-10-26): an old duel push opens the app
      // as a plain tap would.
      expect(shellTabForLink('duel'), isNull);
      expect(shellTabForLink('duel:ABCDEFGHJKMN'), isNull);
    });

    test('the names match what the server sends', () {
      expect(PushLinks.fixtures, 'fixtures');
      expect(PushLinks.league, 'league');
      expect(PushLinks.inbox, 'inbox');
      expect(PushLinks.support, 'support');
      expect(PushLinks.supportInbox, 'support_inbox');
      expect(PushLinks.h2h, 'h2h');
    });
  });
}
