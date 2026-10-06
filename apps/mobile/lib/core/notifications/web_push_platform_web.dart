import 'dart:js_interop';

import 'web_push_platform.dart';

@JS('Notification')
external JSObject? get _notification;

@JS('Notification.permission')
external String get _permission;

@JS('Notification.requestPermission')
external JSPromise<JSString> _requestPermission();

@JS('navigator.serviceWorker')
external JSObject? get _serviceWorker;

@JS('PushManager')
external JSObject? get _pushManager;

@JS('navigator.userAgent')
external String get _userAgent;

@JS('navigator.maxTouchPoints')
external int? get _maxTouchPoints;

@JS('navigator.standalone')
external bool? get _iosStandalone;

@JS('matchMedia')
external _MediaQueryList _matchMedia(String query);

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

@JS('document.baseURI')
external String get _baseUri;

@JS('location.href')
external String get _href;

/// The browser this page runs in.
WebPushPlatform createWebPushPlatform() => const _Browser();

final class _Browser implements WebPushPlatform {
  const _Browser();

  @override
  bool get isWeb => true;

  @override
  bool get isIos {
    final String agent = _userAgent;
    if (agent.contains('iPhone') ||
        agent.contains('iPad') ||
        agent.contains('iPod')) {
      return true;
    }
    // iPadOS reports a Mac; only a touch screen tells them apart.
    return agent.contains('Macintosh') && (_maxTouchPoints ?? 0) > 1;
  }

  @override
  bool get isInstalled =>
      _iosStandalone == true ||
      _matchMedia('(display-mode: standalone)').matches;

  @override
  bool get isSupported =>
      _notification != null && _serviceWorker != null && _pushManager != null;

  @override
  String get permission => isSupported ? _permission : 'unsupported';

  @override
  Future<String> requestPermission() async {
    if (!isSupported) return 'unsupported';
    final JSString answer = await _requestPermission().toDart;
    return answer.toDart;
  }

  @override
  String get workerPath => Uri.parse(_baseUri).resolve(webPushWorkerFile).path;

  @override
  String? launchLink() {
    final String? link = Uri.tryParse(_href)?.queryParameters['push'];
    return link == null || link.isEmpty ? null : link;
  }
}
