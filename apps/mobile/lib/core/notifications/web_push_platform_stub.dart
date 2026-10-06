import 'web_push_platform.dart';

/// Off the web: no browser, nothing to offer.
WebPushPlatform createWebPushPlatform() => const _NotWeb();

final class _NotWeb implements WebPushPlatform {
  const _NotWeb();

  @override
  bool get isWeb => false;

  @override
  bool get isIos => false;

  @override
  bool get isInstalled => false;

  @override
  bool get isSupported => false;

  @override
  String get permission => 'unsupported';

  @override
  Future<String> requestPermission() async => 'unsupported';

  @override
  String get workerPath => webPushWorkerFile;

  @override
  String? launchLink() => null;
}
