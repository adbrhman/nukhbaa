/// Any thrown failure reads as a message (audit L-13): the admin sections
/// cast every error to AppError, so anything else turned a section into a
/// red error screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/error/error_presenter.dart';
import 'package:shared/shared.dart';

void main() {
  test('an AppError reads as itself', () {
    const AppError error = AppError.validation('x.y', 'bad');
    expect(ErrorPresenter.asAppError(error), same(error));
    expect(ErrorPresenter.messageOf(error), ErrorPresenter.message(error));
  });

  test('anything else is a plain transient failure, never a throw', () {
    final AppError coerced = ErrorPresenter.asAppError(TypeError());
    expect(coerced.kind, ErrorKind.transient);
    expect(coerced.code, 'client.unexpected');
    expect(
      ErrorPresenter.messageOf(StateError('boom')),
      ErrorPresenter.message(coerced),
    );
    expect(ErrorPresenter.messageOf(null), ErrorPresenter.message(coerced));
  });
}
