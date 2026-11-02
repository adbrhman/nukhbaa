import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;

/// An [http.Client] that names this app's build on every request it sends
/// ([appBuildHeader], script 142), so the server can refuse a release too
/// old to be served, and the install it runs on ([appInstallHeader],
/// script 200), so the server knows which accounts share a phone.
/// Everything else is the wrapped client's.
final class BuildHeaderClient extends http.BaseClient {
  /// Wraps [inner]; [build] is the release number (`NUKHBA_BUILD_NUMBER`,
  /// 0 for a local run).
  /// [installId] answers this install's id as far as it is known: it never
  /// waits, so no request waits for the secure store. No id (or one that
  /// throws) sends the request without it.
  BuildHeaderClient(
    this._inner, {
    required int build,
    String? Function()? installId,
  }) : _build = '$build',
       _installId = installId;

  final http.Client _inner;
  final String _build;
  final String? Function()? _installId;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers[appBuildHeader] = _build;
    final String? install = _readInstall();
    if (install != null && install.isNotEmpty) {
      request.headers[appInstallHeader] = install;
    }
    return _inner.send(request);
  }

  String? _readInstall() {
    final String? Function()? read = _installId;
    if (read == null) {
      return null;
    }
    try {
      return read();
    } on Object {
      return null;
    }
  }

  @override
  void close() => _inner.close();
}
