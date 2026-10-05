/// The words of the Duels feature: refusals, states, and the share message.
///
/// The server decides every rule; these only say, in Arabic, what it
/// decided. Unknown codes fall back to the app's [ErrorPresenter].
library;

import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

import '../../core/error/error_presenter.dart';
import '../competition/team_registry.dart';
import '../gamification/invite_friends_screen.dart';

/// What the player reads for a refused duel action.
String duelErrorMessage(AppError error) => switch (error.code) {
  'social.duel_prediction_required' =>
    'توقّع المباراة أولاً، ثم تحدَّ أصدقاءك.',
  'social.duel_minimum_lead_time' =>
    'يُنشأ التحدي قبل انطلاق المباراة بـ30 دقيقة على الأقل.',
  'social.duel_max_pending_challenges' =>
    'لديك 10 تحديات مفتوحة. ألغِ بعضها أو انتظر قبولها.',
  'social.duel_challenge_not_found' => 'لا توجد مواجهة بهذا الرمز.',
  'social.duel_code_malformed' ||
  'social.duel_code_empty' => 'رمز المواجهة 12 خانة. تأكد منه وحاول مجدداً.',
  'social.duel_challenge_not_open' => 'هذا التحدي لم يعد مفتوحاً.',
  'social.duel_expired' => 'انطلقت المباراة، فانتهى وقت قبول التحدي.',
  'social.duel_capacity_full' => 'اكتمل عدد المنافسين في هذا التحدي.',
  'social.duel_pair_already_exists' => 'بينكما مواجهة على هذه المباراة من قبل.',
  'social.duel_self_accept' ||
  'social.duel_self_target' => 'لا يمكنك قبول تحديك أنت.',
  'social.duel_wrong_target' => 'هذا التحدي مخصص للاعب آخر.',
  'social.duel_not_challenger' => 'صاحب التحدي وحده يستطيع إلغاءه.',
  'social.duel_not_target' ||
  'social.duel_decline_not_allowed' => 'لا يمكنك رفض هذا التحدي.',
  'social.duel_cancel_not_allowed' => 'لا يمكن إلغاء هذا التحدي.',
  'social.duel_challenger_not_participant' ||
  'social.duel_opponent_not_participant' =>
    'لم تُسجَّل في منافسة الشهر بعد. افتح الرئيسية ثم حاول مجدداً.',
  'social.duel_challenger_inactive' => 'صاحب التحدي لم يعد نشطاً.',
  'social.duel_fixture_not_in_season' => 'هذه المباراة ليست ضمن منافسة الشهر.',
  _ => ErrorPresenter.message(error),
};

/// A challenge state token, in words.
String duelChallengeStateLabel(String state) => switch (state) {
  'open' => 'مفتوح',
  'full' => 'اكتمل',
  'expired' => 'انتهى وقته',
  'cancelled' => 'أُلغي',
  'declined' => 'رُفض',
  _ => state,
};

/// A duel state token, in words.
String duelStateLabel(String state) => switch (state) {
  'upcoming' => 'لم تبدأ',
  'live' => 'جارية',
  'settled' => 'انتهت',
  _ => state,
};

/// A settled duel's outcome token, in words.
String duelOutcomeLabel(String outcome) => switch (outcome) {
  'won' => 'فزت',
  'lost' => 'خسرت',
  'draw' => 'تعادل',
  _ => outcome,
};

/// `Home × Away` with the app's team names.
String duelFixtureTitle(String homeTeam, String awayTeam) =>
    '${teamDisplayName(homeTeam)} × ${teamDisplayName(awayTeam)}';

/// The web app's address with the duel code, like the invitation link.
String duelLinkFor(String code) => '$inviteWebBase?duel=$code';

/// The message shared to friends for [challenge].
String duelShareText(DuelChallengeDto challenge) =>
    '⚔️ تحدّاك ${challenge.challengerName} في مباراة '
    '${duelFixtureTitle(challenge.homeTeam, challenge.awayTeam)} على نُخبة!\n'
    'رمز المواجهة: ${challenge.code}\n'
    '${duelLinkFor(challenge.code)}';
