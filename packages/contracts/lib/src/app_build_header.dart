/// The request header that names the app build sending a request (script
/// 142): the Android and iOS app send their release number
/// (`NUKHBA_BUILD_NUMBER`, 0 for a local run) with every call to the server.
///
/// Builds released before script 142 send nothing. Once
/// `NUKHBA_BUILD_HEADER_SINCE` is set on the server, a request without this
/// header, or from a build older than that number, is refused with an Arabic
/// message telling the player to install the new app; every build since
/// 2026-10-03 shows the server's Arabic message in place of the screen's
/// content.
const String appBuildHeader = 'x-nukhba-build';

/// The request header that names the install of the app sending a request
/// (script 200): the Android app sends its install id (`nukhba.install_id`,
/// a random id kept in the secure store) with every call, so the server
/// knows which accounts share a phone. The web sends none.
const String appInstallHeader = 'x-nukhba-install';
