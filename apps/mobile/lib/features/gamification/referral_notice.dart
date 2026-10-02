/// The invitation refusals a player must be told about in so many words
/// (migration 0086): an invitation counts only from the app, on a phone that
/// is not the inviter's.
///
/// A code typed at sign-up is claimed silently -- the sign-up never fails
/// over an invitation -- so these two outcomes are kept here and shown once
/// over the app by the session gate.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown when a code was used from the browser.
const String referralAppRequiredMessage =
    'الدعوة لا تُحتسب من المتصفح. ثبّت تطبيق نُخبة على جوالك وسجّل الدخول، '
    'ثم أدخل رمز الدعوة من صفحة «ادعُ أصدقاءك» خلال 24 ساعة من إنشاء حسابك.';

/// Shown when a code was used on the inviter's own phone.
const String referralSameDeviceMessage =
    'لا تُقبل الدعوة من جوال صاحب الرابط. يجب أن يسجّل المدعو من جواله هو. '
    'حسابك يعمل طبيعياً، لكن الدعوة لم تُحتسب.';

/// The notice owed for a claim [status], or null when none is.
String? referralDeviceNotice(String status) => switch (status) {
  'app_required' => referralAppRequiredMessage,
  'same_device' => referralSameDeviceMessage,
  _ => null,
};

/// The notice waiting to be shown, if any.
final class ReferralNotice extends Notifier<String?> {
  @override
  String? build() => null;

  /// Keeps [message] until it is shown.
  void show(String message) => state = message;

  /// Drops the notice once it is on screen.
  void clear() => state = null;
}

/// The invitation notice waiting to be shown.
final referralNoticeProvider = NotifierProvider<ReferralNotice, String?>(
  ReferralNotice.new,
);
