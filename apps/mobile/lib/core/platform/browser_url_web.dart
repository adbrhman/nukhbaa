import 'dart:js_interop';

import 'reset_url.dart';

@JS('history.replaceState')
external void _replaceState(JSAny? state, JSString title, JSString url);

@JS('location.reload')
external void _reload();

/// Reloads the page, which loads the build the server now holds.
void reloadPage() => _reload();

/// Removes the password-reset URL from the browser address bar
/// without reloading the Flutter application. The bar keeps the app's own
/// page; the site's root is the landing page (audit L-10).
void clearPasswordResetUrl() {
  _replaceState(null, ''.toJS, appPathAfterPasswordReset(Uri.base).toJS);
}
