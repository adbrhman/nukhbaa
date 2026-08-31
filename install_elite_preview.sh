#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/home/dev/nukhbaa-backup-1787537565"
PREVIEW_DIR="$PROJECT_DIR/lib/elite_preview"

echo "=============================================="
echo " NUKHBAA ELITE UI — SAFE PREVIEW INSTALLER"
echo "=============================================="

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: Project directory not found:"
  echo "$PROJECT_DIR"
  exit 1
fi

cd "$PROJECT_DIR"

if [ ! -f "pubspec.yaml" ]; then
  echo "ERROR: pubspec.yaml not found."
  exit 1
fi

echo
echo "[1/5] Creating preview directory..."
mkdir -p "$PREVIEW_DIR"

echo "[2/5] Writing Elite Design System..."

cat > "$PREVIEW_DIR/elite_preview.dart" <<'DART'
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NukhbaaElitePreviewApp());
}

class C {
  static const bg = Color(0xFF08070D);
  static const surface = Color(0xFF111019);
  static const surface2 = Color(0xFF181522);
  static const surface3 = Color(0xFF211B30);

  static const purple = Color(0xFF7C3AED);
  static const purpleLight = Color(0xFFA855F7);
  static const purpleDark = Color(0xFF4C1D95);

  static const gold = Color(0xFFF5C451);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);

  static const text = Color(0xFFF8F7FB);
  static const secondary = Color(0xFFA6A1B5);
  static const muted = Color(0xFF6E687D);
  static const border = Color(0xFF2A2438);
}

class NukhbaaElitePreviewApp extends StatelessWidget {
  const NukhbaaElitePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nukhbaa Elite Preview',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: C.bg,
        colorScheme: const ColorScheme.dark(
          primary: C.purple,
          secondary: C.gold,
          surface: C.surface,
          error: C.red,
        ),
      ),
      builder: (_, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  final pages = const [
    HomePage(),
    MatchesPage(),
    PredictionPage(),
    LeaderboardPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: pages,
      ),
      bottomNavigationBar: BottomNav(
        index: index,
        onChanged: (value) => setState(() => index = value),
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const BottomNav({
    super.key,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF20D0B13),
        border: Border(
          top: BorderSide(
            color: C.border,
            width: .7,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              item(
                0,
                Icons.home_outlined,
                Icons.home_rounded,
                'الرئيسية',
              ),
              item(
                1,
                Icons.sports_soccer_outlined,
                Icons.sports_soccer,
                'المباريات',
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(2),
                  child: Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      transform: Matrix4.translationValues(0, -12, 0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            C.purpleLight,
                            C.purple,
                          ],
                        ),
                        border: Border.all(
                          color: C.bg,
                          width: 5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: C.purple.withOpacity(.45),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
              item(
                2,
                Icons.bolt_outlined,
                Icons.bolt_rounded,
                'توقعاتي',
              ),
              item(
                4,
                Icons.person_outline_rounded,
                Icons.person_rounded,
                'الحساب',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget item(
    int itemIndex,
    IconData normal,
    IconData active,
    String label,
  ) {
    final selected = index == itemIndex;

    return Expanded(
      child: InkWell(
        onTap: () => onChanged(itemIndex),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? active : normal,
              size: 22,
              color: selected
                  ? C.purpleLight
                  : C.secondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.w800 : FontWeight.w500,
                color: selected
                    ? C.purpleLight
                    : C.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 110),
        children: [
          const Header(),
          const SizedBox(height: 22),

          const Text(
            'مرحبًا 👋',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'جاهز لتثبت أنك الأفضل؟',
            style: TextStyle(
              color: C.secondary,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 18),

          const StatsCard(),

          const SizedBox(height: 20),

          const Section(
            title: 'مباراة اليوم',
            action: 'عرض الكل',
          ),

          const MatchCard(),

          const SizedBox(height: 20),

          const Section(title: 'وصول سريع'),

          const QuickActions(),

          const SizedBox(height: 20),

          const Section(
            title: 'المنافسة',
            action: 'عرض الترتيب',
          ),

          const CompetitionCard(),
        ],
      ),
    );
  }
}

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'NUKHBAA',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),

        const Spacer(),

        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: C.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: C.border),
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            size: 21,
          ),
        ),

        const SizedBox(width: 10),

        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                C.gold,
                C.purple,
              ],
            ),
          ),
          child: const Icon(
            Icons.person_rounded,
          ),
        ),
      ],
    );
  }
}

class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            C.purpleDark,
            Color(0xFF20142F),
            C.surface,
          ],
        ),
        border: Border.all(
          color: C.purple.withOpacity(.55),
        ),
        boxShadow: [
          BoxShadow(
            color: C.purple.withOpacity(.15),
            blurRadius: 30,
          ),
        ],
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Stat(
                  value: '2,480',
                  label: 'نقاطك',
                ),
              ),
              DividerVertical(),
              Expanded(
                child: Stat(
                  value: '#126',
                  label: 'ترتيبك',
                  gold: true,
                ),
              ),
              DividerVertical(),
              Expanded(
                child: Stat(
                  value: '78%',
                  label: 'الدقة',
                  green: true,
                ),
              ),
            ],
          ),

          SizedBox(height: 18),

          Divider(
            color: Color(0x182FFFFFF),
            height: 1,
          ),

          SizedBox(height: 13),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.trending_up_rounded,
                color: C.green,
                size: 17,
              ),
              SizedBox(width: 5),
              Text(
                '+12',
                style: TextStyle(
                  color: C.green,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 5),
              Text(
                'مركز هذا الأسبوع',
                style: TextStyle(
                  color: C.secondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DividerVertical extends StatelessWidget {
  const DividerVertical({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 55,
      color: Colors.white.withOpacity(.08),
    );
  }
}

class Stat extends StatelessWidget {
  final String value;
  final String label;
  final bool gold;
  final bool green;

  const Stat({
    super.key,
    required this.value,
    required this.label,
    this.gold = false,
    this.green = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: gold
                ? C.gold
                : green
                    ? C.green
                    : Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: C.secondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class Section extends StatelessWidget {
  final String title;
  final String? action;

  const Section({
    super.key,
    required this.title,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          if (action != null)
            Text(
              action!,
              style: const TextStyle(
                color: C.purpleLight,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class MatchCard extends StatelessWidget {
  const MatchCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: C.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_outlined,
                color: C.gold,
                size: 17,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'الدوري الإنجليزي الممتاز',
                  style: TextStyle(
                    color: C.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: C.orange.withOpacity(.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'قريبًا',
                  style: TextStyle(
                    color: C.orange,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 21),

          Row(
            children: [
              Expanded(
                child: team(
                  'أرسنال',
                  Icons.shield_rounded,
                ),
              ),

              const Column(
                children: [
                  Text(
                    '20:30',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'اليوم',
                    style: TextStyle(
                      color: C.secondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),

              Expanded(
                child: team(
                  'ليفربول',
                  Icons.shield_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              probability('1', '45%'),
              const SizedBox(width: 7),
              probability('X', '28%'),
              const SizedBox(width: 7),
              probability('2', '27%'),
            ],
          ),

          const SizedBox(height: 13),

          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: C.orange,
                size: 14,
              ),
              SizedBox(width: 5),
              Text(
                'يغلق التوقع خلال 02:14:32',
                style: TextStyle(
                  color: C.secondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget team(String name, IconData icon) {
    return Column(
      children: [
        Container(
          width: 55,
          height: 55,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.surface2,
            border: Border.all(color: C.border),
          ),
          child: Icon(
            icon,
            size: 30,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget probability(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: C.surface2,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: C.purple.withOpacity(.35),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: C.purpleLight,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: C.secondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.sports_soccer_rounded, 'المباريات'),
      (Icons.bolt_rounded, 'توقعاتي'),
      (Icons.groups_rounded, 'مجموعاتي'),
      (Icons.leaderboard_rounded, 'المتصدرون'),
    ];

    return Row(
      children: actions.map((action) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 7),
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.border),
            ),
            child: Column(
              children: [
                Icon(
                  action.$1,
                  color: C.purpleLight,
                  size: 23,
                ),
                const SizedBox(height: 8),
                Text(
                  action.$2,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class CompetitionCard extends StatelessWidget {
  const CompetitionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: C.border),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: C.gold.withOpacity(.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: C.gold,
            ),
          ),

          const SizedBox(width: 13),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المتصدرون العالميون',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'تنافس مع أفضل المتنبئين',
                  style: TextStyle(
                    color: C.secondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 15,
            color: C.muted,
          ),
        ],
      ),
    );
  }
}

class MatchesPage extends StatelessWidget {
  const MatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
        children: const [
          PageTitle(title: 'المباريات'),
          SizedBox(height: 18),
          DateTabs(),
          SizedBox(height: 18),
          Section(title: 'الدوري الإنجليزي الممتاز'),
          MatchCard(),
          SizedBox(height: 12),
          MatchCard(),
          SizedBox(height: 18),
          Section(title: 'الدوري الإسباني'),
          MatchCard(),
        ],
      ),
    );
  }
}

class DateTabs extends StatelessWidget {
  const DateTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          tab('لاحقًا', false),
          tab('غدًا', false),
          tab('اليوم', true),
        ],
      ),
    );
  }

  Widget tab(String text, bool active) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? C.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? Colors.white : C.secondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  int home = 2;
  int away = 1;
  String result = '1';
  double confidence = .76;
  bool doublePrediction = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
        physics: const BouncingScrollPhysics(),
        children: [
          const PageTitle(title: 'توقع النتيجة'),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: C.border),
            ),
            child: Column(
              children: [
                const Text(
                  'الدوري الإنجليزي الممتاز',
                  style: TextStyle(
                    color: C.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    team('أرسنال'),
                    const Column(
                      children: [
                        Text(
                          '20:30',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'اليوم',
                          style: TextStyle(
                            color: C.secondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    team('ليفربول'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'النتيجة المتوقعة',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              score(
                home,
                (v) {
                  if (home > 0) {
                    setState(() => home--);
                  }
                },
                () {
                  if (home < 20) {
                    setState(() => home++);
                  }
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 13),
                child: Text(
                  ':',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              score(
                away,
                (v) {
                  if (away > 0) {
                    setState(() => away--);
                  }
                },
                () {
                  if (away < 20) {
                    setState(() => away++);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 23),

          const Text(
            'من سيفوز؟',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              choice('1', 'أرسنال'),
              const SizedBox(width: 7),
              choice('X', 'تعادل'),
              const SizedBox(width: 7),
              choice('2', 'ليفربول'),
            ],
          ),

          const SizedBox(height: 23),

          Row(
            children: [
              const Text(
                'مستوى الثقة',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${(confidence * 100).round()}%',
                style: const TextStyle(
                  color: C.purpleLight,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          Slider(
            value: confidence,
            onChanged: (value) {
              setState(() => confidence = value);
            },
          ),

          GestureDetector(
            onTap: () {
              setState(() {
                doublePrediction = !doublePrediction;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: doublePrediction
                    ? C.gold.withOpacity(.08)
                    : C.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: doublePrediction
                      ? C.gold
                      : C.border,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.close_rounded,
                    color: C.gold,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الدبل ×2',
                          style: TextStyle(
                            color: C.gold,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'ضاعف نقاطك إذا كان توقعك صحيحًا',
                          style: TextStyle(
                            color: C.secondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    doublePrediction
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: doublePrediction
                        ? C.gold
                        : C.muted,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.bolt_rounded),
              label: const Text(
                'تأكيد التوقع',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: C.purple,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget team(String name) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: C.surface2,
              border: Border.all(color: C.border),
            ),
            child: const Icon(
              Icons.shield_rounded,
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget score(
    int value,
    ValueChanged<int> minus,
    VoidCallback plus,
  ) {
    return Expanded(
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: C.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: C.purple.withOpacity(.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () => minus(value),
              icon: const Icon(Icons.remove_rounded),
            ),
            Text(
              '$value',
              style: const TextStyle(
                color: C.purpleLight,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            IconButton(
              onPressed: plus,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget choice(String value, String title) {
    final selected = result == value;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => result = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? C.purple : C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? C.purpleLight
                  : C.border,
            ),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: selected
                      ? Colors.white70
                      : C.secondary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
        children: [
          const PageTitle(title: 'المتصدرون'),
          const SizedBox(height: 20),
          const Podium(),
          const SizedBox(height: 20),
          rank('4', 'خالد', '2,890'),
          rank('5', 'يوسف', '2,750'),
          rank('6', 'أنت', '2,480', current: true),
          rank('7', 'سلمان', '2,310'),
        ],
      ),
    );
  }

  Widget rank(
    String number,
    String name,
    String points, {
    bool current = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: current
            ? C.purple.withOpacity(.14)
            : C.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current ? C.purple : C.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              number,
              style: TextStyle(
                color: current
                    ? C.purpleLight
                    : C.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const CircleAvatar(
            radius: 18,
            backgroundColor: C.surface3,
            child: Icon(
              Icons.person_rounded,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            points,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class Podium extends StatelessWidget {
  const Podium({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 235,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          podium('2', 'محمد', '3,110', 165, Colors.grey),
          podium('1', 'أحمد', '3,240', 210, C.gold),
          podium('3', 'علي', '2,980', 145, const Color(0xFFCD7F32)),
        ],
      ),
    );
  }

  Widget podium(
    String rank,
    String name,
    String points,
    double height,
    Color color,
  ) {
    return Expanded(
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(.07),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(18),
          ),
          border: Border.all(
            color: color.withOpacity(.55),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C.surface2,
                border: Border.all(
                  color: color,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.person_rounded,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '#$rank',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              name,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              points,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
        children: [
          const PageTitle(title: 'الحساب'),
          const SizedBox(height: 25),

          Center(
            child: Column(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        C.gold,
                        C.purple,
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'عبدالرحمن',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'متنبئ محترف',
                  style: TextStyle(
                    color: C.secondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.border),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Stat(
                    value: '2,480',
                    label: 'النقاط',
                  ),
                ),
                Expanded(
                  child: Stat(
                    value: '78%',
                    label: 'الدقة',
                  ),
                ),
                Expanded(
                  child: Stat(
                    value: '126',
                    label: 'الترتيب',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          menu(Icons.emoji_events_outlined, 'إنجازاتي'),
          menu(Icons.groups_outlined, 'مجموعاتي'),
          menu(Icons.history_rounded, 'سجل التوقعات'),
          menu(Icons.notifications_none_rounded, 'الإشعارات'),
          menu(Icons.settings_outlined, 'الإعدادات'),
        ],
      ),
    );
  }

  Widget menu(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: C.border),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: C.purpleLight,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_left_rounded,
            color: C.muted,
          ),
        ],
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  final String title;

  const PageTitle({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.tune_rounded,
          color: C.secondary,
        ),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Spacer(),
        const Icon(
          Icons.more_horiz_rounded,
          color: C.secondary,
        ),
      ],
    );
  }
}
DART

echo "[3/5] Validating Dart source..."

dart format "$PREVIEW_DIR/elite_preview.dart" >/dev/null

if ! dart analyze "$PREVIEW_DIR/elite_preview.dart" >/dev/null 2>&1; then
  echo
  echo "ERROR: Dart analyzer failed."
  echo "Run:"
  echo "dart analyze $PREVIEW_DIR/elite_preview.dart"
  exit 1
fi

echo "[4/5] Checking Flutter project..."

flutter pub get

echo "[5/5] Installation complete."
echo
echo "=============================================="
echo " NUKHBAA ELITE PREVIEW READY"
echo "=============================================="
echo
echo "IMPORTANT:"
echo "Existing main.dart was NOT modified."
echo "Existing routes/providers/repositories were NOT modified."
echo
echo "Run the new UI with:"
echo
echo "cd $PROJECT_DIR"
echo "flutter run -t lib/elite_preview/elite_preview.dart"
echo
echo "Or on a connected Android device:"
echo
echo "flutter run -d android -t lib/elite_preview/elite_preview.dart"
echo
echo "To return to the original application:"
echo "just stop the preview and run the normal Flutter project."
echo
