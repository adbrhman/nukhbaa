import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;

/// An [http.Client] that names this app's build on every request it sends
/// ([appBuildHeader], script 142), so the server can refuse a release too
/// old to be served. Everything else is the wrapped client's.
final class BuildHeaderClient extends http.BaseClient {
  /// Wraps [inner]; [build] is the release number (`NUKHBA_BUILD_NUMBER`,
  /// 0 for a local run).
  BuildHeaderClient(this._inner, {required int build}) : _build = '$build';

  final http.Client _inner;
  final String _build;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers[appBuildHeader] = _build;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
