import 'package:api_client/api_client.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers this device's FCM registration token with the server, so the
/// "you have not predicted yet" reminder has somewhere to arrive.
///
/// Android only. The web build carries no Firebase configuration, so every
/// entry point returns early on [kIsWeb]; `dart:io` is deliberately not
/// imported here, since it does not compile for the web at all.
///
/// Failures are swallowed (logged in debug): a device that cannot register
/// loses a reminder, and that must never cost the user a frame or a session.
class PushTokenService {
  /// Creates the service over the typed identity client.
  PushTokenService(this._authApi);

  final AuthApi _authApi;

  bool _listening = false;

  bool _listeningForLinks = false;

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Requests notification permission, registers the current token, and starts
  /// listening for refreshes. Safe to call on every app start: the server
  /// upserts on the token itself, so a repeat is a no-op re-confirmation.
  Future<void> registerCurrentDevice() async {
    if (kIsWeb) {
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

  /// Calls [onLink] with the `link` of the push that opened the app: the
  /// one that launched it, then every later tap while it runs. A push with
  /// no link, and the web build, call nothing.
  Future<void> listenForOpenedPushes(void Function(String link) onLink) async {
    if (kIsWeb || _listeningForLinks) {
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
