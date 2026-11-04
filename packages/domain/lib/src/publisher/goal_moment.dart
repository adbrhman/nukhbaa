import 'package:domain/src/publisher/score_line.dart';

/// What a goal meant for its match, which picks the words of its post.
enum GoalMoment {
  /// The first goal of the match.
  opener('opener', key: true),

  /// Brings the sides level.
  equaliser('equaliser', key: true),

  /// Puts the scoring side ahead from level.
  goAhead('go_ahead', key: true),

  /// Adds to a lead the scoring side already had.
  extendsLead('extends_lead', key: false),

  /// Narrows a deficit without levelling.
  reducesDeficit('reduces_deficit', key: false),

  /// Levels the match from the [lateMinute] on.
  lateEqualiser('late_equaliser', key: true),

  /// Puts the scoring side ahead from level from the [lateMinute] on.
  lateWinner('late_winner', key: true);

  const GoalMoment(this.wire, {required this.key});

  /// The stored name. A storage contract: never renamed.
  final String wire;

  /// Whether a platform set to post key goals only posts it.
  final bool key;

  /// From this minute on, a goal that levels or leads is a late one.
  static const int lateMinute = 85;

  /// The moment named [wire]; null for a name not known here.
  static GoalMoment? fromWire(String wire) {
    for (final moment in GoalMoment.values) {
      if (moment.wire == wire) {
        return moment;
      }
    }
    return null;
  }

  /// What [step] meant, the clock reading [minute] (null when not known,
  /// which never makes a goal a late one).
  static GoalMoment of(GoalStep step, {int? minute}) {
    final before = step.before;
    final after = step.after;
    final late = minute != null && minute >= lateMinute;
    if (before == ScoreLine.nil) {
      return late ? GoalMoment.lateWinner : GoalMoment.opener;
    }
    if (after.level) {
      return late ? GoalMoment.lateEqualiser : GoalMoment.equaliser;
    }
    if (before.level) {
      return late ? GoalMoment.lateWinner : GoalMoment.goAhead;
    }
    final scorerLeadsAfter = step.home ? after.homeLeads : after.awayLeads;
    return scorerLeadsAfter
        ? GoalMoment.extendsLead
        : GoalMoment.reducesDeficit;
  }

  /// The minute as a number from a clock label: `"45+2"` is 45, `"90"` is
  /// 90; null for a label that is not a minute.
  static int? minuteOf(String? label) {
    if (label == null) {
      return null;
    }
    return int.tryParse(label.split('+').first.trim());
  }
}
