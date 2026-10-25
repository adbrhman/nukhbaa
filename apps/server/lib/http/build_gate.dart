import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// The oldest app build the server still serves, from
/// `NUKHBA_BUILD_HEADER_SINCE` in [environment] (script 142); `null` -- the
/// gate is off -- when the variable is absent, empty, not a number or not
/// above zero.
///
/// The owner sets it on Northflank once the release that sends
/// [appBuildHeader] can be downloaded, to that release's number; removing
/// it lets every build in again.
int? minServedBuild(Map<String, String> environment) {
  final String? raw = environment['NUKHBA_BUILD_HEADER_SINCE']?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final int? value = int.tryParse(raw);
  return value == null || value <= 0 ? null : value;
}

/// What a build too old to be served reads in place of the screen's content.
///
/// Arabic, so every build since 2026-10-03 shows it as it is
/// (`ErrorPresenter`, a `409` with an envelope is an invariant): a player
/// who ignores every notification still reads it on every screen and on the
/// sign-in screen. The builds before 2026-10-18 are another Android app
/// (`com.example.mobile`), so the new one installs beside them.
///
/// The old screen shows it as plain text, so the link cannot be tapped
/// (script 143). It names the old app's own buttons first: «تسجيل الدخول
/// بحساب آخر» clears the session on the phone and opens the sign-in screen,
/// whose «يتوفر تحديث جديد» row (every build since 2026-10-13) installs the
/// release matching the phone's processor; the builds before it have only
/// the link.
const String oldBuildMessage =
    'نسختك من نُخبة قديمة ولم تعد تعمل. للتحديث اضغط «تسجيل الدخول بحساب '
    'آخر» ثم «يتوفر تحديث جديد». إن لم يظهر، حمّل النسخة الجديدة من '
    'links.nukhbaa.app. بعدها افتح نُخبة الجديد وسجّل الدخول بنفس حسابك، '
    'واحذف القديم إن بقي. نقاطك وتوقعاتك محفوظة.';

/// The paths every build may still reach: the update check (the old
/// builds' own "update available" row reads it) and the health checks.
const Set<String> _alwaysOpen = <String>{'/', '/health', '/app/latest-build'};

/// The refusal for a request too old to be served, or `null` to serve it.
///
/// Off while [minBuild] is `null`. A browser request (one with an `Origin`
/// header) is the web build, which reloads to the newest release by itself
/// and sends no build header, so it passes; so does a local run (build 0).
/// Any other request needs [appBuildHeader] naming a build of at least
/// [minBuild].
AppError? oldBuildRefusal({
  required String path,
  required Map<String, String> headers,
  required int? minBuild,
}) {
  if (minBuild == null) {
    return null;
  }
  final String trimmed = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  if (_alwaysOpen.contains(trimmed) || headers['origin'] != null) {
    return null;
  }
  final String? raw = headers[appBuildHeader];
  final int? build = raw == null ? null : int.tryParse(raw.trim());
  if (build == 0 || (build != null && build >= minBuild)) {
    return null;
  }
  return const AppError.invariant('app.update_required', oldBuildMessage);
}

/// Whether a request with [headers] comes from an app build that names no
/// build (every build before script 142): no [appBuildHeader] and no
/// `Origin` (the web build). Such a request is refused for a player on a
/// retired build while an admin holds a minimum (script 149, `bearerAuth`).
bool sentNoBuild(Map<String, String> headers) =>
    headers[appBuildHeader] == null && headers['origin'] == null;

/// The refusal a player on a retired build reads (script 149): the same
/// words as the gate's.
const AppError retiredBuildRefusal = AppError.invariant(
  'app.update_required',
  oldBuildMessage,
);

/// The root middleware's gate: answers a request too old to be served with
/// [oldBuildMessage] (`409`, the uniform error envelope) before it reaches
/// any route or the database.
Middleware buildGate({required int? minBuild}) {
  return (Handler handler) {
    return (RequestContext context) {
      final AppError? refusal = oldBuildRefusal(
        path: context.request.uri.path,
        headers: context.request.headers,
        minBuild: minBuild,
      );
      if (refusal != null) {
        return errorResponse(refusal);
      }
      return handler(context);
    };
  };
}
