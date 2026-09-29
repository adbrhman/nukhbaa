import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? state, JSString title, JSString url);

@JS('location.reload')
external void _reload();

/// Reloads the page, which loads the build the server now holds.
void reloadPage() => _reload();

/// Removes the password-reset URL from the browser address bar
/// without reloading the Flutter application.
void clearPasswordResetUrl() {
  _replaceState(null, ''.toJS, '/'.toJS);
}
