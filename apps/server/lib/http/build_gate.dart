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

/// The oldest build served (script 148): the higher of
/// `NUKHBA_BUILD_HEADER_SINCE` ([fromEnvironment]) and the minimum an admin
/// raised from the dashboard ([fromAdmin], migration 0113); `null`, the gate
/// off, when neither is set. The admin's button turns the refusal on and
/// off: once the variable is removed from Northflank, clearing the minimum
/// lets every build in again.
int? servedMinimum({required int? fromEnvironment, required int? fromAdmin}) {
  if (fromEnvironment == null) {
    return fromAdmin != null && fromAdmin > 0 ? fromAdmin : null;
  }
  if (fromAdmin == null || fromAdmin <= fromEnvironment) {
    return fromEnvironment;
  }
  return fromAdmin;
}

/// Whether [path] with [headers] is refused at all by a gate that is on:
/// false for the always-open paths, a browser and a local run (build 0).
bool _gated(String path, Map<String, String> headers) {
  final String trimmed = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  if (_alwaysOpen.contains(trimmed) || headers['origin'] != null) {
    return false;
  }
  return _buildOf(headers) != 0;
}

/// The build named by [appBuildHeader], or null without one.
int? _buildOf(Map<String, String> headers) {
  final String? raw = headers[appBuildHeader];
  return raw == null ? null : int.tryParse(raw.trim());
}

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
  if (minBuild == null || !_gated(path, headers)) {
    return null;
  }
  final int? build = _buildOf(headers);
  if (build != null && build >= minBuild) {
    return null;
  }
  return const AppError.invariant('app.update_required', oldBuildMessage);
}

/// The root middleware's gate: answers a request too old to be served with
/// [oldBuildMessage] (`409`, the uniform error envelope) before it reaches
/// any route or the database.
///
/// [minBuild] is the variable's; [adminMinimum], when given, reads the
/// admin's minimum (cached in the process, script 148) for a request the
/// gate may refuse, and the higher of the two applies ([servedMinimum]). An
/// unreadable minimum is no minimum: the gate never shuts the service by
/// mistake.
Middleware buildGate({
  required int? minBuild,
  Future<int?> Function()? adminMinimum,
}) {
  return (Handler handler) {
    return (RequestContext context) async {
      final String path = context.request.uri.path;
      final Map<String, String> headers = context.request.headers;
      if (!_gated(path, headers)) {
        return handler(context);
      }
      int? fromAdmin;
      if (adminMinimum != null) {
        try {
          fromAdmin = await adminMinimum();
        } on Object {
          fromAdmin = null;
        }
      }
      final AppError? refusal = oldBuildRefusal(
        path: path,
        headers: headers,
        minBuild: servedMinimum(
          fromEnvironment: minBuild,
          fromAdmin: fromAdmin,
        ),
      );
      if (refusal != null) {
        return errorResponse(refusal);
      }
      return handler(context);
    };
  };
}

/// The admin's minimum as the root middleware hands it to [buildGate]:
/// [read] (the composition root's `ReadMinSupportedBuild`), null on a
/// failure.
Future<int?> adminMinimumFrom(Future<Result<int?>> Function() read) async {
  final Result<int?> result = await read();
  return switch (result) {
    Ok<int?>(:final value) => value,
    Err<int?>() => null,
  };
}
