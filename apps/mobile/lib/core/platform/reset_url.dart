/// What a web address says about the password-reset flow, as pure
/// functions of the address so they can be checked anywhere.
library;

/// Whether [url] is a password-reset link: the `/reset-password` page, or
/// a Supabase link whose fragment carries a session for a recovery
/// (`type=recovery`). A sign-up confirmation also carries `access_token`
/// in its fragment, with `type=signup`: it is not a reset and opens the app
/// as usual (audit M-02).
bool isPasswordResetUrl(Uri url) {
  if (url.path.endsWith('/reset-password')) return true;
  final String fragment = url.fragment;
  return fragment.contains('access_token=') &&
      RegExp(r'(?:^|[#?&])type=recovery(?:$|&)').hasMatch(fragment);
}

/// Where the address bar goes once the reset is done: the app's own page
/// (`/nukhbaa/` when served there), without the link's query or fragment
/// -- never the site's root, which is the landing page (audit L-10).
String appPathAfterPasswordReset(Uri url) {
  const String page = 'reset-password';
  String path = url.path;
  if (path.endsWith('/$page')) {
    path = path.substring(0, path.length - page.length);
  }
  return path.isEmpty ? '/' : path;
}
