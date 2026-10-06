/// What the browser offers for push notifications (phase 3 of the plan:
/// the iPhone players, who use the web build, get pushes too). Android
/// never reads it: [webPushPlatform] there is a stub that says "not web".
///
/// On an iPhone a page can be sent pushes only once it is added to the home
/// screen and opened from there (iOS 16.4 and later), and the browser asks
/// for permission only from a tap.
library;

import 'package:firebase_core/firebase_core.dart';

import 'web_push_platform_stub.dart'
    if (dart.library.js_interop) 'web_push_platform_web.dart'
    as impl;

/// The browser, as far as pushes go.
abstract interface class WebPushPlatform {
  /// Running in a browser.
  bool get isWeb;

  /// An iPhone or iPad.
  bool get isIos;

  /// Opened from the home screen rather than a browser tab.
  bool get isInstalled;

  /// The browser can show pushes: notifications, a service worker and a
  /// push manager.
  bool get isSupported;

  /// `default`, `granted` or `denied`; `unsupported` when [isSupported] is
  /// false.
  String get permission;

  /// Asks the player; must run from their tap. The answer, as [permission].
  Future<String> requestPermission();

  /// The absolute path of the push service worker.
  String get workerPath;

  /// The `push` link of the page's address: where the push the player
  /// tapped should open; null when the app was opened otherwise.
  String? launchLink();
}

/// This build's browser (a stub off the web).
final WebPushPlatform webPushPlatform = impl.createWebPushPlatform();

/// The Firebase web app `nukhbaa-web` (project nukhbaa-65501). These keys
/// identify the app to Firebase and are public by design: every web page
/// that uses Firebase serves them.
const FirebaseOptions webFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyA68ckLGYYzp6ubV1suhE7atvIpKC_WMJU',
  appId: '1:117694325386:web:b3f6a3e2b90efb957b4373',
  messagingSenderId: '117694325386',
  projectId: 'nukhbaa-65501',
  authDomain: 'nukhbaa-65501.firebaseapp.com',
  storageBucket: 'nukhbaa-65501.firebasestorage.app',
);

/// The public half of the project's Web Push key pair (Cloud Messaging ->
/// Web Push certificates), which the browser's push service checks.
const String webPushVapidKey =
    'BDa_mH4GBRS42ywF3Izkv3DErG9DR_Fqt10oxU2ksCqmSnvo1TUn30mPy5IvRet2OE72gguGXZP-9RIKsEpEerM';

/// The push service worker, relative to the site's base address. It lives
/// in its own folder so its scope never meets the page's own.
const String webPushWorkerFile = 'push/firebase-messaging-sw.js';

/// What the web build offers the player about pushes.
enum WebPushOffer {
  /// Nothing: not the web, not supported, or already answered.
  none,

  /// An iPhone in a browser tab: add the app to the home screen first.
  install,

  /// Ask the player to turn pushes on.
  enable,
}

/// What [platform] offers now.
WebPushOffer webPushOfferFor(WebPushPlatform platform) {
  if (!platform.isWeb) return WebPushOffer.none;
  if (platform.isIos && !platform.isInstalled) return WebPushOffer.install;
  if (!platform.isSupported) return WebPushOffer.none;
  return platform.permission == 'default'
      ? WebPushOffer.enable
      : WebPushOffer.none;
}
