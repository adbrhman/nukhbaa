import 'package:domain/src/publisher/goal_moment.dart';
import 'package:domain/src/publisher/publish_platform.dart';
import 'package:domain/src/publisher/score_line.dart';

/// What a goal post says.
final class GoalPostFacts {
  /// Creates the facts.
  const GoalPostFacts({
    required this.league,
    required this.homeName,
    required this.awayName,
    required this.step,
    required this.moment,
    this.scorer,
    this.minuteLabel,
    this.penalty = false,
    this.ownGoal = false,
  });

  /// The competition's Arabic name.
  final String league;

  /// The home club's Arabic name.
  final String homeName;

  /// The away club's Arabic name.
  final String awayName;

  /// The goal.
  final GoalStep step;

  /// What it meant.
  final GoalMoment moment;

  /// The player, when the provider named him.
  final String? scorer;

  /// The clock as the provider writes it (`"45+2"`), when known.
  final String? minuteLabel;

  /// Scored from the penalty spot.
  final bool penalty;

  /// An own goal: [scorer] is a player of the other side.
  final bool ownGoal;

  /// The side that scored.
  String get teamName => step.home ? homeName : awayName;
}

/// What a final-result post says.
final class FinalPostFacts {
  /// Creates the facts.
  const FinalPostFacts({
    required this.league,
    required this.homeName,
    required this.awayName,
    required this.score,
    this.scorers = const <String>[],
  });

  /// The competition's Arabic name.
  final String league;

  /// The home club's Arabic name.
  final String homeName;

  /// The away club's Arabic name.
  final String awayName;

  /// The recorded result.
  final ScoreLine score;

  /// The goals as lines ready to print (`"سالم الدوسري 45+2'"`), in order;
  /// empty when not known.
  final List<String> scorers;
}

/// What a correction says when a posted goal was ruled out.
final class GoalCancelFacts {
  /// Creates the facts.
  const GoalCancelFacts({
    required this.league,
    required this.homeName,
    required this.awayName,
    required this.cancelled,
    required this.scoreNow,
    this.minuteLabel,
  });

  /// The competition's Arabic name.
  final String league;

  /// The home club's Arabic name.
  final String homeName;

  /// The away club's Arabic name.
  final String awayName;

  /// The goal ruled out.
  final GoalStep cancelled;

  /// The score without it.
  final ScoreLine scoreNow;

  /// The clock of the goal ruled out, when known.
  final String? minuteLabel;
}

/// The words of every post, written for each platform: an editorial post on
/// Facebook, a caption with tags under the picture on Instagram, a short
/// update on X (owner's brief, 2026-11-04).
///
/// Each kind has several wordings; [seedOf] a stable key picks one, so two
/// goals of one match rarely read alike and a re-run writes the same words.
/// X posts carry no link (a link costs more there and is not needed).
final class PostCopy {
  const PostCopy._();

  /// The most an X post may weigh ([xLength]).
  static const int xLimit = 280;

  /// The tag every post on Instagram and X carries.
  static const String brandTag = '#نخبة';

  /// The words of a goal post on [platform].
  static String goal(
    PublishPlatform platform,
    GoalPostFacts facts, {
    required int seed,
  }) {
    final headline = PostCopy.headline(facts.moment);
    final team = facts.teamName;
    final line = scoreLine(facts.homeName, facts.step.after, facts.awayName);
    final scorer = _scorerPhrase(facts);
    final minute = facts.minuteLabel;
    final atMinute = minute == null ? null : 'الدقيقة $minute';
    final sentence = _sentence(scorer, minute);
    switch (platform) {
      case PublishPlatform.facebook:
        {
          final variants = <List<String?>>[
            <String?>[
              '⚽ $headline ${forTeam(team)}!',
              scorer == null ? null : 'المسجّل: $scorer',
              line,
              _dotted(<String?>[facts.league, atMinute]),
            ],
            <String?>[
              '$team يسجّل ⚽',
              sentence,
              'النتيجة الآن: $line',
              facts.league,
            ],
            <String?>[
              '$headline في مباراة ${facts.homeName} و${facts.awayName}',
              line,
              _dotted(<String?>[scorer, atMinute]),
              facts.league,
            ],
          ];
          return _lines(variants[seed.abs() % variants.length]);
        }
      case PublishPlatform.instagram:
        {
          final tags = '$brandTag ${hashtag(facts.league)} #كرة_القدم';
          final variants = <List<String?>>[
            <String?>[
              '$headline ⚽',
              line,
              _dotted(<String?>[scorer, atMinute]),
              '',
              tags,
            ],
            <String?>['$team يسجّل!', line, sentence, '', tags],
          ];
          return _lines(variants[seed.abs() % variants.length]);
        }
      case PublishPlatform.x:
        {
          final detail = _spaced(<String?>[
            scorer,
            minute == null ? null : "$minute'",
          ]);
          final variants = <String>[
            _lines(<String?>[
              '⚽ $headline ${forTeam(team)} | $line',
              detail,
              brandTag,
            ]),
            _lines(<String?>['$team يسجّل ⚽ $line', detail, brandTag]),
          ];
          return _fitX(<String>[
            variants[seed.abs() % variants.length],
            _lines(<String?>['⚽ $line', brandTag]),
          ]);
        }
    }
  }

  /// The words of a final-result post on [platform].
  static String finalResult(
    PublishPlatform platform,
    FinalPostFacts facts, {
    required int seed,
  }) {
    final line = scoreLine(facts.homeName, facts.score, facts.awayName);
    final verdict = PostCopy.verdict(facts);
    final goals = facts.scorers.isEmpty
        ? null
        : 'الأهداف: ${facts.scorers.join('، ')}';
    switch (platform) {
      case PublishPlatform.facebook:
        final variants = <List<String?>>[
          <String?>['صافرة النهاية 🏁', line, verdict, goals, facts.league],
          <String?>[
            'انتهت المباراة: $line',
            '$verdict في ${facts.league}',
            goals,
          ],
        ];
        return _lines(variants[seed.abs() % variants.length]);
      case PublishPlatform.instagram:
        return _lines(<String?>[
          'النتيجة النهائية 🏁',
          line,
          verdict,
          '',
          '$brandTag ${hashtag(facts.league)} #كرة_القدم',
        ]);
      case PublishPlatform.x:
        return _fitX(<String>[
          _lines(<String?>['🏁 النهاية | $line', verdict, brandTag]),
          _lines(<String?>['🏁 $line', brandTag]),
        ]);
    }
  }

  /// The words of a correction on [platform] for a posted goal the VAR
  /// ruled out.
  static String goalCancelled(PublishPlatform platform, GoalCancelFacts facts) {
    final team = facts.cancelled.home ? facts.homeName : facts.awayName;
    final minute = facts.minuteLabel;
    final line = scoreLine(facts.homeName, facts.scoreNow, facts.awayName);
    final text = _lines(<String?>[
      'تصحيح: ألغى حكم الفيديو هدف $team'
          '${minute == null ? '' : ' في الدقيقة $minute'}.',
      'النتيجة: $line',
      if (platform == PublishPlatform.facebook) facts.league else brandTag,
    ]);
    return platform == PublishPlatform.x
        ? _fitX(<String>[
            text,
            _lines(<String?>['تصحيح: $line', brandTag]),
          ])
        : text;
  }

  /// `«الهلال 2 - 1 النصر»`: each side's goals next to its name when read
  /// right to left.
  static String scoreLine(String home, ScoreLine score, String away) =>
      '$home ${score.home} - ${score.away} $away';

  /// «للهلال», «لـريال مدريد»: the Arabic "for" joined to a club's name.
  static String forTeam(String team) {
    final name = team.trim();
    if (name.startsWith('ال')) {
      return 'لل${name.substring(2)}';
    }
    return 'لـ$name';
  }

  /// [words] as one tag: `#دوري_روشن_السعودي`.
  static String hashtag(String words) {
    final joined = words
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), '');
    return '#$joined';
  }

  /// A stable seed for [key]: 32-bit FNV-1a over its UTF-16 code units, the
  /// same in every run (unlike `String.hashCode`).
  static int seedOf(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// The weight X counts for [text]: one for each character of the Latin,
  /// Arabic and other scripts below U+1100 and of a few punctuation ranges,
  /// two for anything else (an emoji).
  static int xLength(String text) {
    var weight = 0;
    for (final rune in text.runes) {
      final light =
          rune <= 4351 ||
          (rune >= 8192 && rune <= 8205) ||
          (rune >= 8208 && rune <= 8223) ||
          (rune >= 8242 && rune <= 8247);
      weight += light ? 1 : 2;
    }
    return weight;
  }

  static String _fitX(List<String> candidates) {
    for (final candidate in candidates) {
      if (xLength(candidate) <= xLimit) {
        return candidate;
      }
    }
    final last = candidates.last;
    final cut = StringBuffer();
    var weight = 0;
    for (final rune in last.runes) {
      final next = xLength(String.fromCharCode(rune));
      if (weight + next > xLimit) {
        break;
      }
      cut.writeCharCode(rune);
      weight += next;
    }
    return cut.toString();
  }

  /// The big words of a goal that meant [moment]: «هدف التقدم».
  static String headline(GoalMoment moment) => switch (moment) {
    GoalMoment.opener => 'الهدف الأول',
    GoalMoment.equaliser => 'هدف التعادل',
    GoalMoment.goAhead => 'هدف التقدم',
    GoalMoment.extendsLead => 'هدف جديد',
    GoalMoment.reducesDeficit => 'تقليص الفارق',
    GoalMoment.lateEqualiser => 'تعادل في الأنفاس الأخيرة',
    GoalMoment.lateWinner => 'هدف قاتل',
  };

  static String? _scorerPhrase(GoalPostFacts facts) {
    final scorer = facts.scorer?.trim();
    if (scorer == null || scorer.isEmpty) {
      return null;
    }
    if (facts.ownGoal) {
      return '$scorer بالخطأ في مرماه';
    }
    if (facts.penalty) {
      return '$scorer من ركلة جزاء';
    }
    return scorer;
  }

  static String? _sentence(String? scorer, String? minute) {
    if (scorer != null && minute != null) {
      return '$scorer في الدقيقة $minute.';
    }
    if (scorer != null) {
      return '$scorer.';
    }
    if (minute != null) {
      return 'في الدقيقة $minute.';
    }
    return null;
  }

  /// «فوز الهلال», «تعادل الهلال والنصر».
  static String verdict(FinalPostFacts facts) {
    if (facts.score.homeLeads) {
      return 'فوز ${facts.homeName}';
    }
    if (facts.score.awayLeads) {
      return 'فوز ${facts.awayName}';
    }
    return 'تعادل ${facts.homeName} و${facts.awayName}';
  }

  static String? _dotted(List<String?> parts) {
    final kept = parts.whereType<String>().toList();
    return kept.isEmpty ? null : kept.join(' • ');
  }

  static String? _spaced(List<String?> parts) {
    final kept = parts.whereType<String>().toList();
    return kept.isEmpty ? null : kept.join(' ');
  }

  static String _lines(List<String?> lines) =>
      lines.whereType<String>().join('\n');
}
