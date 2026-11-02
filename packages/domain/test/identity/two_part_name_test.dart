/// A new account's name is a real one (asked 2026-11-02, refined by the
/// owner 2026-11-03): a first name and a father's name or a surname --
/// never one name, never a surname alone or first, never an alias.
/// Through the domain rule registration validates with.
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

String? _refusal(String name) => switch (User.validateNewAccountName(name)) {
  Ok<String>() => null,
  Err<String>(:final error) => error.code,
};

void main() {
  test('a first name with a surname or a father\'s name is kept', () {
    for (final String name in <String>[
      'طارق العبسي',
      'طارق محمد',
      'محمد العماري',
      'محمد طاهر',
      'عبد الله المغربي',
      'محمد عبد الرحمن',
      'أبو بكر الطاهري',
      'محمد بن سلمان',
      'محمد آل سعود',
      'محمد محمد',
      'الحسن علي',
      'مُحَمَّد عَلِي',
      'Mohammed Ali',
    ]) {
      expect(_refusal(name), isNull, reason: name);
    }
  });

  test('one name is refused', () {
    for (final String name in <String>[
      'علي',
      'طارق',
      'عز',
      'ليث',
      'عبد الرحمن',
      'عبدالرحمن',
      'أبو محمد',
      'محمد بن',
      'م علي',
      'محمد ـــ',
    ]) {
      expect(
        _refusal(name),
        'identity.display_name_not_two_part',
        reason: name,
      );
    }
  });

  test('a surname alone, or first, is refused', () {
    for (final String name in <String>[
      'المغربي الرفاعي',
      'المغربي المغربي',
      'الطاهري الطاهري',
      'العماري محمد',
      'المغربي',
      'آل سعود',
    ]) {
      expect(
        _refusal(name),
        'identity.display_name_surname_first',
        reason: name,
      );
    }
  });

  test('an alias is refused', () {
    for (final String name in <String>[
      'ملك الجمال',
      'ملك التوقع',
      'ساهر الليل',
      'عاشق الهلال',
      'الزعيم محمد',
      'قناص التوقعات',
      'محمد 10',
      'King Ali',
    ]) {
      expect(_refusal(name), 'identity.display_name_alias', reason: name);
    }
  });

  test('each refusal says what to write, in Arabic', () {
    for (final AppError error in <AppError>[
      User.notTwoPartName,
      User.surnameFirstName,
      User.aliasName,
    ]) {
      expect(error.message, contains('محمد العماري'));
    }
  });

  test('the older rules still come first', () {
    expect(_refusal('   '), 'identity.display_name_empty');
    expect(_refusal('دعم نُخبة'), 'identity.display_name_reserved');
  });

  test('an admin rename keeps the old rule: one word still passes', () {
    expect(User.validateDisplayName('خالد'), isA<Ok<String>>());
  });
}
