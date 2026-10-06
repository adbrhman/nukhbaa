import 'package:api_client/api_client.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'web_push_platform.dart';

/// Registers this device's FCM registration token with the server, so the
/// "you have not predicted yet" reminder has somewhere to arrive.
///
/// On Android, at every start. On the web (the iPhone players, phase 3 of
/// the plan), only once the player turned pushes on from a tap
/// ([registerWebDevice], from the home page's card): Firebase starts then,
/// with the web app's configuration, never before the first frame; once
/// allowed, the token is refreshed at every start. `dart:io` is
/// deliberately not imported here, since it does not compile for the web.
///
/// Failures are swallowed (logged in debug): a device that cannot register
/// loses a reminder, and that must never cost the user a frame or a session.
class PushTokenService {
  /// Creates the service over the typed identity client; [webPush] is the
  /// browser, for tests.
  PushTokenService(this._authApi, {WebPushPlatform? webPush})
    : _webPush = webPush ?? webPushPlatform;

  final AuthApi _authApi;

  final WebPushPlatform _webPush;

  /// How long the web waits for Firebase or a token: the scripts come from
  /// Google's servers, which some networks block.
  static const Duration webTimeout = Duration(seconds: 15);

  bool _listening = false;

  bool _listeningForLinks = false;

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Requests notification permission, registers the current token, and starts
  /// listening for refreshes. Safe to call on every app start: the server
  /// upserts on the token itself, so a repeat is a no-op re-confirmation.
  Future<void> registerCurrentDevice() async {
    if (kIsWeb) {
      // The browser asks only from the player's tap; once they allowed,
      // the token is refreshed here.
      if (_webPush.permission == 'granted') {
        await registerWebDevice();
      }
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _register(token);
      }

      // FCM rotates a token on reinstall, restore, and app-data clear. Without
      // this listener the row would point at a dead address until the next
      // launch.
      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen(_register);
      }
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('PushTokenService: registration failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  /// On the web, once the player allowed pushes: starts Firebase with the
  /// web app's configuration and registers this browser's token. False when
  /// it could not (blocked scripts, no token, a refused registration).
  Future<bool> registerWebDevice() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: webFirebaseOptions,
        ).timeout(webTimeout);
      }
      final String? token = await _webToken();
      if (token == null || token.isEmpty) {
        return false;
      }
      final result = await _authApi.registerDeviceToken(
        token: token,
        platform: 'web',
      );
      return result.isOk;
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('PushTokenService: web registration failed: $error');
      }
      return false;
    }
  }

  /// The browser's token. The push worker is registered by the first call
  /// and is not active yet when it subscribes: Safari refuses then, and the
  /// plugin retries only on Chrome's wording. So it is asked again, a
  /// second apart, while the worker activates.
  Future<String?> _webToken() async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await FirebaseMessaging.instance
            .getToken(
              vapidKey: webPushVapidKey,
              serviceWorkerScriptPath: _webPush.workerPath,
            )
            .timeout(webTimeout);
      } on Object {
        if (attempt == 3) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Calls [onLink] with the `link` of the push that opened the app: the
  /// one that launched it, then every later tap while it runs. A push with
  /// no link calls nothing. On the web, the link the push worker opened the
  /// app with (`?push=`).
  ///
  /// [onForegroundPush] is called for every push that arrives while the app
  /// is open: Android shows no banner for those, so the app refreshes what
  /// they change instead (the bell's count).
  Future<void> listenForOpenedPushes(
    void Function(String link) onLink, {
    void Function()? onForegroundPush,
  }) async {
    if (_listeningForLinks) {
      return;
    }
    if (kIsWeb) {
      // The push worker opens the app with ?push=<link>.
      _listeningForLinks = true;
      final String? link = _webPush.launchLink();
      if (link != null) {
        // After the frame being built: the link may open a page.
        await Future<void>.delayed(Duration.zero);
        onLink(link);
      }
      return;
    }
    try {
      _listeningForLinks = true;
      final messaging = FirebaseMessaging.instance;
      final RemoteMessage? initial = await messaging.getInitialMessage();
      final Object? first = initial?.data['link'];
      if (first is String) {
        onLink(first);
      }
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final Object? link = message.data['link'];
        if (link is String) {
          onLink(link);
        }
      });
      final void Function()? onForeground = onForegroundPush;
      if (onForeground != null) {
        FirebaseMessaging.onMessage.listen((_) => onForeground());
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('PushTokenService: push links unavailable: $error');
      }
    }
  }

  Future<void> _register(String token) async {
    final result = await _authApi.registerDeviceToken(
      token: token,
      platform: _platform,
    );
    if (kDebugMode && result.isErr) {
      debugPrint('PushTokenService: the server rejected the token');
    }
  }
}
