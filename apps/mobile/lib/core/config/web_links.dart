/// The web addresses the app shares: the web app a league link opens, and
/// the site a shared card points to.
library;

/// CI's NUKHBA_INVITE_BASE_URL: the Northflank web mirror, which opens in
/// Yemen, where github.io is blocked. Empty when not set.
const String _inviteBaseFromBuild = String.fromEnvironment(
  'NUKHBA_INVITE_BASE_URL',
);

/// The web app's address. The site at nukhbaa.app unless the build names
/// another host: it opens in Yemen, where github.io is blocked (audit M-03).
const String inviteWebBase = _inviteBaseFromBuild == ''
    ? 'https://nukhbaa.app/nukhbaa/'
    : _inviteBaseFromBuild;

/// The link a shared card carries (audit M-13): the site's landing page, at
/// the root of the host that serves the web app under `/nukhbaa/` -- the
/// same `https://nukhbaa.app` a shared match card carries. GitHub Pages has
/// no landing page of ours, so a link there opens the web app itself.
String appSiteLink({String webBase = inviteWebBase}) {
  final Uri base = Uri.parse(webBase);
  if (base.host != 'adbrhman.github.io' && base.path == '/nukhbaa/') {
    return base.replace(path: '').toString();
  }
  return webBase;
}
