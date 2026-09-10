import 'package:shared/shared.dart';

/// Outbound port for delivering a push notification.
///
/// Implemented by `FcmPushSender` (FCM HTTP v1). The use-case above it knows
/// nothing about Firebase, OAuth, or HTTP.
abstract interface class PushSender {
  /// Sends one notification to every token in [tokens].
  ///
  /// Returns the subset of [tokens] the transport rejected as PERMANENTLY
  /// invalid (unregistered device, malformed token) so the caller can retire
  /// them. A transient failure is NOT in that list -- it is a `Result.err`, or
  /// simply an absent entry, because retiring a token over a network blip
  /// would silently unsubscribe a real user.
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
  });
}
