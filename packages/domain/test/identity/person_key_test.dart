import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// Script 263: the key two accounts of one person share -- the first and
/// the last part of the name, whatever the spelling around them.
void main() {
  test('one person under several spellings shares one key', () {
    final Set<String?> keys = <String?>{
      for (final String name in <String>[
        'عبدالرحمن المغربي',
        'عبد الرحمن المغربي',
        'عبدالرحمن محمد المغربي',
        'عبدُالرحمن  المغربى',
        'عبد الرحمن بن محمد المغربي',
      ])
        User.personKey(name),
    };

    expect(keys, <String?>{'عبدالرحمن المغربي'});
  });

  test('hamza, taa marbuta and tatweel do not count', () {
    expect(User.personKey('أسامة الأحمد'), User.personKey('اسامه الاحمـد'));
  });

  test('another first or last name is another person', () {
    expect(
      User.personKey('عبدالرحمن المغربي'),
      isNot(User.personKey('عبدالله المغربي')),
    );
    expect(
      User.personKey('عبدالرحمن المغربي'),
      isNot(User.personKey('عبدالرحمن الرفاعي')),
    );
  });

  test('a name of one part has no key', () {
    expect(User.personKey('محمد'), isNull);
    expect(User.personKey('عبد الرحمن'), isNull);
    expect(User.personKey('محمد بن'), isNull);
    expect(User.personKey('  '), isNull);
  });

  test('the key keeps the order: the first and the last part', () {
    expect(User.personKey('محمد علي'), 'محمد علي');
    expect(User.personKey('علي محمد'), 'علي محمد');
  });
}
