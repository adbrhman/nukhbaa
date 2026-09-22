import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/notifications/push_link.dart';

void main() {
  group('shellTabForLink', () {
    test('each known link opens its tab', () {
      expect(shellTabForLink(PushLinks.fixtures), 1);
      expect(shellTabForLink(PushLinks.league), 3);
      expect(shellTabForLink(PushLinks.inbox), 0);
    });

    test('an unknown link opens nothing in particular', () {
      expect(shellTabForLink('something-newer'), isNull);
    });

    test('the names match what the server sends', () {
      expect(PushLinks.fixtures, 'fixtures');
      expect(PushLinks.league, 'league');
      expect(PushLinks.inbox, 'inbox');
    });
  });
}
