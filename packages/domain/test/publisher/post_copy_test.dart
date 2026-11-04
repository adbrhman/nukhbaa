import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  const step = GoalStep(home: true, before: ScoreLine(1, 1));
  const facts = GoalPostFacts(
    league: 'دوري روشن السعودي',
    homeName: 'الهلال',
    awayName: 'النصر',
    step: step,
    moment: GoalMoment.goAhead,
    scorer: 'سالم الدوسري',
    minuteLabel: '45+2',
  );

  group('PostCopy.goal', () {
    test('every wording on every platform names the score and the scorer', () {
      for (final platform in PublishPlatform.values) {
        for (var seed = 0; seed < 6; seed++) {
          final text = PostCopy.goal(platform, facts, seed: seed);

          expect(text, contains('الهلال 2 - 1 النصر'), reason: platform.wire);
          expect(text, contains('سالم الدوسري'), reason: platform.wire);
          expect(text, contains('45+2'), reason: platform.wire);
        }
      }
    });

    test('the three platforms never read the same', () {
      final seed = PostCopy.seedOf('fixture-1:h2');
      final texts = <String>{
        for (final platform in PublishPlatform.values)
          PostCopy.goal(platform, facts, seed: seed),
      };

      expect(texts, hasLength(PublishPlatform.values.length));
    });

    test('Facebook has several wordings, picked by the seed', () {
      final texts = <String>{
        for (var seed = 0; seed < 3; seed++)
          PostCopy.goal(PublishPlatform.facebook, facts, seed: seed),
      };

      expect(texts, hasLength(3));
    });

    test('tags go on Instagram and X, not on Facebook', () {
      for (var seed = 0; seed < 3; seed++) {
        expect(
          PostCopy.goal(PublishPlatform.facebook, facts, seed: seed),
          isNot(contains('#')),
        );
        expect(
          PostCopy.goal(PublishPlatform.instagram, facts, seed: seed),
          contains('#دوري_روشن_السعودي'),
        );
        expect(
          PostCopy.goal(PublishPlatform.x, facts, seed: seed),
          contains(PostCopy.brandTag),
        );
      }
    });

    test('no post carries a link', () {
      for (final platform in PublishPlatform.values) {
        for (var seed = 0; seed < 3; seed++) {
          expect(
            PostCopy.goal(platform, facts, seed: seed),
            isNot(contains('http')),
          );
        }
      }
    });

    test('a goal with no scorer known names the side and the minute', () {
      const unnamed = GoalPostFacts(
        league: 'الدوري الإنجليزي',
        homeName: 'ليفربول',
        awayName: 'أرسنال',
        step: GoalStep(home: false, before: ScoreLine.nil),
        moment: GoalMoment.opener,
        minuteLabel: '12',
      );

      for (final platform in PublishPlatform.values) {
        for (var seed = 0; seed < 3; seed++) {
          final text = PostCopy.goal(platform, unnamed, seed: seed);

          expect(text, contains('ليفربول 0 - 1 أرسنال'));
          expect(text, contains('12'));
          expect(text, isNot(contains('null')));
        }
      }
    });

    test('a penalty and an own goal are said so', () {
      const penalty = GoalPostFacts(
        league: 'الدوري الإسباني',
        homeName: 'برشلونة',
        awayName: 'ريال مدريد',
        step: GoalStep(home: true, before: ScoreLine.nil),
        moment: GoalMoment.opener,
        scorer: 'ليفاندوفسكي',
        minuteLabel: '30',
        penalty: true,
      );
      const ownGoal = GoalPostFacts(
        league: 'الدوري الإسباني',
        homeName: 'برشلونة',
        awayName: 'ريال مدريد',
        step: GoalStep(home: false, before: ScoreLine(1, 0)),
        moment: GoalMoment.equaliser,
        scorer: 'كوندي',
        minuteLabel: '55',
        ownGoal: true,
      );

      expect(
        PostCopy.goal(PublishPlatform.facebook, penalty, seed: 0),
        contains('من ركلة جزاء'),
      );
      expect(
        PostCopy.goal(PublishPlatform.facebook, ownGoal, seed: 0),
        contains('بالخطأ في مرماه'),
      );
    });

    test('an X post stays within 280 even with very long names', () {
      final long = GoalPostFacts(
        league: 'بطولة ' * 20,
        homeName: 'نادي ${'طويل ' * 30}',
        awayName: 'نادي ${'أطول ' * 30}',
        step: step,
        moment: GoalMoment.goAhead,
        scorer: 'لاعب ${'باسم ' * 20}',
        minuteLabel: '90+7',
      );

      for (var seed = 0; seed < 3; seed++) {
        expect(
          PostCopy.xLength(PostCopy.goal(PublishPlatform.x, long, seed: seed)),
          lessThanOrEqualTo(PostCopy.xLimit),
        );
      }
    });
  });

  group('PostCopy.finalResult', () {
    test('says who won, or that it was a draw', () {
      FinalPostFacts result(int home, int away) => FinalPostFacts(
        league: 'دوري روشن السعودي',
        homeName: 'الهلال',
        awayName: 'النصر',
        score: ScoreLine(home, away),
      );

      expect(
        PostCopy.finalResult(PublishPlatform.facebook, result(2, 1), seed: 0),
        contains('فوز الهلال'),
      );
      expect(
        PostCopy.finalResult(PublishPlatform.instagram, result(0, 1), seed: 0),
        contains('فوز النصر'),
      );
      expect(
        PostCopy.finalResult(PublishPlatform.x, result(1, 1), seed: 0),
        contains('تعادل الهلال والنصر'),
      );
    });

    test('lists the scorers on Facebook when they are known', () {
      const result = FinalPostFacts(
        league: 'دوري روشن السعودي',
        homeName: 'الهلال',
        awayName: 'النصر',
        score: ScoreLine(1, 0),
        scorers: <String>["سالم الدوسري 45+2'"],
      );

      for (var seed = 0; seed < 2; seed++) {
        expect(
          PostCopy.finalResult(PublishPlatform.facebook, result, seed: seed),
          contains("الأهداف: سالم الدوسري 45+2'"),
        );
      }
    });
  });

  group('PostCopy.goalCancelled', () {
    test('names the side, the minute and the score without the goal', () {
      const cancel = GoalCancelFacts(
        league: 'الدوري الفرنسي',
        homeName: 'باريس إف سي',
        awayName: 'رين',
        cancelled: GoalStep(home: false, before: ScoreLine(2, 1)),
        scoreNow: ScoreLine(2, 1),
        minuteLabel: '51',
      );

      for (final platform in PublishPlatform.values) {
        final text = PostCopy.goalCancelled(platform, cancel);

        expect(text, contains('ألغى حكم الفيديو هدف رين'));
        expect(text, contains('باريس إف سي 2 - 1 رين'));
        expect(text, contains('51'));
      }
    });
  });

  group('helpers', () {
    test('forTeam joins the article as Arabic does', () {
      expect(PostCopy.forTeam('الهلال'), 'للهلال');
      expect(PostCopy.forTeam('ريال مدريد'), 'لـريال مدريد');
    });

    test('hashtag joins words and drops punctuation', () {
      expect(PostCopy.hashtag('دوري روشن السعودي'), '#دوري_روشن_السعودي');
      expect(PostCopy.hashtag('Ligue 1 (France)'), '#Ligue_1_France');
    });

    test('seedOf is stable and spreads keys', () {
      expect(PostCopy.seedOf('abc'), PostCopy.seedOf('abc'));
      expect(PostCopy.seedOf('abc'), 0x1a47e90b);
      expect(
        PostCopy.seedOf('fixture:h1'),
        isNot(PostCopy.seedOf('fixture:h2')),
      );
    });

    test('xLength counts Arabic once and an emoji twice', () {
      expect(PostCopy.xLength('هدف'), 3);
      expect(PostCopy.xLength('⚽'), 2);
      expect(PostCopy.xLength('🏁'), 2);
    });
  });
}
