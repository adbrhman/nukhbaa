import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? state, JSString title, JSString url);

/// Removes the password-reset URL from the browser address bar
/// without reloading the Flutter application.
void clearPasswordResetUrl() {
  _replaceState(null, ''.toJS, '/'.toJS);
}
