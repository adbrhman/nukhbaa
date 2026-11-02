/// A new account's name is a two-part name (decided 2026-11-02), through
/// the domain rule registration validates with.
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  test('a single name is refused, with the reason', () {
    final Result<String> result = User.validateNewAccountName(
      ' \u062e\u0627\u0644\u062f ',
    );

    expect(
      (result as Err<String>).error.code,
      'identity.display_name_not_two_part',
    );
    expect(
      result.error.message,
      contains('\u0627\u0644\u062b\u0646\u0627\u0626\u064a'),
    );
  });

  test('a two-part name is kept, trimmed', () {
    final Result<String> result = User.validateNewAccountName(
      '  \u0645\u062d\u0645\u062f   \u0639\u0644\u064a ',
    );

    expect(
      (result as Ok<String>).value,
      '\u0645\u062d\u0645\u062f   \u0639\u0644\u064a',
    );
  });

  test('the older rules still come first', () {
    expect(
      (User.validateNewAccountName('   ') as Err<String>).error.code,
      'identity.display_name_empty',
    );
    expect(
      (User.validateNewAccountName(
                '\u062f\u0639\u0645 \u0646\u064f\u062e\u0628\u0629',
              )
              as Err<String>)
          .error
          .code,
      'identity.display_name_reserved',
    );
  });

  test('an admin rename keeps the old rule: one word still passes', () {
    expect(
      User.validateDisplayName('\u062e\u0627\u0644\u062f'),
      isA<Ok<String>>(),
    );
  });
}
