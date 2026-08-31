import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/admin_hub_screen.dart';
import '../competition/team_logo_assets.dart';
import 'session_controller.dart';

class NukhbaaColors {
  static const background = Color(0xFF08070D);
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

ThemeData nukhbaaTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: NukhbaaColors.background,
    fontFamily: 'IBMPlexSansArabic',
    colorScheme: const ColorScheme.dark(
      primary: NukhbaaColors.purple,
      secondary: NukhbaaColors.gold,
      surface: NukhbaaColors.surface,
      error: NukhbaaColors.red,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xF00D0B13),
      indicatorColor: Color(0x337C3AED),
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class NukhbaaShell extends ConsumerStatefulWidget {
  final AuthenticatedUserDto user;

  const NukhbaaShell({required this.user, super.key});

  @override
  ConsumerState<NukhbaaShell> createState() => _NukhbaaShellState();
}

class _NukhbaaShellState extends ConsumerState<NukhbaaShell> {
  int currentIndex = 0;

  List<Widget> get pages => [
    const NukhbaaHomePage(),
    const NukhbaaMatchesPage(),
    const NukhbaaPredictionsPage(),
    const NukhbaaLeaderboardPage(),
    NukhbaaProfilePage(
      user: widget.user,
      onSignOut: () => ref.read(sessionControllerProvider.notifier).signOut(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: nukhbaaTheme(),
        child: Scaffold(
          extendBody: true,
          body: IndexedStack(index: currentIndex, children: pages),
          bottomNavigationBar: NukhbaaBottomNav(
            index: currentIndex,
            onChanged: (index) {
              setState(() => currentIndex = index);
            },
          ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
// Shared UI
/* -------------------------------------------------------------------------- */

class NukhbaaBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const NukhbaaBottomNav({
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
          top: BorderSide(color: NukhbaaColors.border, width: 0.7),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _item(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'الرئيسية',
                index: 0,
              ),
              _item(
                icon: Icons.sports_soccer_outlined,
                activeIcon: Icons.sports_soccer,
                label: 'المباريات',
                index: 1,
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
                            NukhbaaColors.purpleLight,
                            NukhbaaColors.purple,
                          ],
                        ),
                        border: Border.all(
                          color: NukhbaaColors.background,
                          width: 5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: NukhbaaColors.purple.withValues(alpha: .45),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              _item(
                icon: Icons.bolt_outlined,
                activeIcon: Icons.bolt_rounded,
                label: 'توقعاتي',
                index: 2,
              ),
              _item(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'الحساب',
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final active = this.index == index;

    return Expanded(
      child: InkWell(
        onTap: () => onChanged(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              size: 22,
              color: active
                  ? NukhbaaColors.purpleLight
                  : NukhbaaColors.secondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? NukhbaaColors.purpleLight
                    : NukhbaaColors.secondary,
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: NukhbaaColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  color: NukhbaaColors.purpleLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TeamLogo extends StatelessWidget {
  final String name;
  final IconData icon;

  const TeamLogo({
    super.key,
    required this.name,
    this.icon = Icons.sports_soccer,
  });

  @override
  Widget build(BuildContext context) {
    final String? assetPath = teamLogoAssetPath(name);
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        shape: BoxShape.circle,
        border: Border.all(color: NukhbaaColors.border),
      ),
      child: assetPath == null
          ? Icon(icon, color: Colors.white, size: 30)
          : Image.asset(
              assetPath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(icon, color: Colors.white, size: 30),
            ),
    );
  }
}

/* -------------------------------------------------------------------------- */
// Home
/* -------------------------------------------------------------------------- */

class NukhbaaHomePage extends StatelessWidget {
  const NukhbaaHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 110),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _HomeHeader(),
                const SizedBox(height: 22),
                const _Welcome(),
                const SizedBox(height: 18),
                const _StatsCard(),
                const SizedBox(height: 18),
                const SectionHeader(title: 'مباريات اليوم', action: 'عرض الكل'),
                const MatchCard(
                  competition: 'الدوري الإنجليزي الممتاز',
                  home: 'أرسنال',
                  away: 'ليفربول',
                  time: '20:30',
                  homeProbability: 45,
                  drawProbability: 28,
                  awayProbability: 27,
                ),
                const SizedBox(height: 18),
                const SectionHeader(title: 'وصول سريع'),
                const _QuickActions(),
                const SizedBox(height: 18),
                const SectionHeader(title: 'المنافسة', action: 'عرض الترتيب'),
                const _CompetitionPreview(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'NUKHBAA',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
          ),
        ),
        const Spacer(),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: NukhbaaColors.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: NukhbaaColors.border),
          ),
          child: Stack(
            children: [
              const Center(
                child: Icon(Icons.notifications_none_rounded, size: 21),
              ),
              Positioned(
                top: 8,
                right: 9,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: NukhbaaColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [NukhbaaColors.gold, NukhbaaColors.purple],
            ),
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'مرحبًا 👋',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 5),
        Text(
          'جاهز لتثبت أنك الأفضل؟',
          style: TextStyle(color: NukhbaaColors.secondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF4C1D95), Color(0xFF20142F), Color(0xFF111019)],
        ),
        border: Border.all(color: NukhbaaColors.purple.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: NukhbaaColors.purple.withValues(alpha: .15),
            blurRadius: 30,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _stat(value: '2,480', label: 'نقاطك'),
              ),
              Container(
                width: 1,
                height: 55,
                color: Colors.white.withValues(alpha: .1),
              ),
              Expanded(
                child: _stat(
                  value: '#126',
                  label: 'ترتيبك العالمي',
                  gold: true,
                ),
              ),
              Container(
                width: 1,
                height: 55,
                color: Colors.white.withValues(alpha: .1),
              ),
              Expanded(
                child: _stat(value: '78%', label: 'دقة توقعاتك', green: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: .08)),
          const SizedBox(height: 13),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.trending_up_rounded,
                color: NukhbaaColors.green,
                size: 17,
              ),
              SizedBox(width: 5),
              Text(
                '+12',
                style: TextStyle(
                  color: NukhbaaColors.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 5),
              Text(
                'مركز هذا الأسبوع',
                style: TextStyle(color: NukhbaaColors.secondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String value,
    required String label,
    bool gold = false,
    bool green = false,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: gold
                ? NukhbaaColors.gold
                : green
                ? NukhbaaColors.green
                : Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: NukhbaaColors.secondary, fontSize: 10),
        ),
      ],
    );
  }
}

class MatchCard extends StatelessWidget {
  final String competition;
  final String home;
  final String away;
  final String time;
  final int homeProbability;
  final int drawProbability;
  final int awayProbability;

  const MatchCard({
    super.key,
    required this.competition,
    required this.home,
    required this.away,
    required this.time,
    required this.homeProbability,
    required this.drawProbability,
    required this.awayProbability,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NukhbaaColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_outlined,
                color: NukhbaaColors.gold,
                size: 17,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  competition,
                  style: const TextStyle(
                    color: NukhbaaColors.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: NukhbaaColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _team(away, Icons.shield_outlined)),
              Column(
                children: [
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'اليوم',
                    style: TextStyle(
                      color: NukhbaaColors.secondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: _team(home, Icons.shield_outlined, reversed: true),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _probability('فوز $home', '1', homeProbability),
              const SizedBox(width: 7),
              _probability('تعادل', 'X', drawProbability),
              const SizedBox(width: 7),
              _probability('فوز $away', '2', awayProbability),
            ],
          ),
          const SizedBox(height: 13),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: NukhbaaColors.orange,
                size: 14,
              ),
              SizedBox(width: 5),
              Text(
                'يغلق التوقع خلال 02:14:32',
                style: TextStyle(color: NukhbaaColors.secondary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _team(String name, IconData icon, {bool reversed = false}) {
    final content = Column(
      children: [
        TeamLogo(name: name, icon: icon),
        const SizedBox(height: 7),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );

    return reversed
        ? Align(alignment: Alignment.centerRight, child: content)
        : Align(alignment: Alignment.centerLeft, child: content);
  }

  Widget _probability(String label, String value, int percentage) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: NukhbaaColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: NukhbaaColors.purple.withValues(alpha: .35),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: NukhbaaColors.purpleLight,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$percentage%',
              style: const TextStyle(
                color: NukhbaaColors.secondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.sports_soccer_rounded, 'المباريات'),
      (Icons.bolt_rounded, 'توقعاتي'),
      (Icons.groups_rounded, 'مجموعاتي'),
      (Icons.emoji_events_rounded, 'المتصدرون'),
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 7),
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: NukhbaaColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NukhbaaColors.border),
            ),
            child: Column(
              children: [
                Icon(item.$1, color: NukhbaaColors.purpleLight, size: 23),
                const SizedBox(height: 8),
                Text(
                  item.$2,
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

class _CompetitionPreview extends StatelessWidget {
  const _CompetitionPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NukhbaaColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: NukhbaaColors.gold.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: NukhbaaColors.gold,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المتصدرون العالميون',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'تنافس مع أفضل المتنبئين',
                  style: TextStyle(
                    color: NukhbaaColors.secondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 15,
            color: NukhbaaColors.muted,
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
// Matches
/* -------------------------------------------------------------------------- */

class NukhbaaMatchesPage extends StatelessWidget {
  const NukhbaaMatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _PageTitle(
                  title: 'المباريات',
                  leftIcon: Icons.filter_alt_outlined,
                  rightIcon: Icons.calendar_today_outlined,
                ),
                const SizedBox(height: 18),
                const _DateTabs(),
                const SizedBox(height: 18),
                const SectionHeader(title: 'الدوري الإنجليزي الممتاز'),
                const MatchCard(
                  competition: 'الدوري الإنجليزي الممتاز',
                  home: 'أرسنال',
                  away: 'ليفربول',
                  time: '20:30',
                  homeProbability: 45,
                  drawProbability: 28,
                  awayProbability: 27,
                ),
                const SizedBox(height: 12),
                const MatchCard(
                  competition: 'الدوري الإنجليزي الممتاز',
                  home: 'مانشستر سيتي',
                  away: 'تشيلسي',
                  time: '23:00',
                  homeProbability: 50,
                  drawProbability: 25,
                  awayProbability: 25,
                ),
                const SizedBox(height: 18),
                const SectionHeader(title: 'الدوري الإسباني'),
                const MatchCard(
                  competition: 'الدوري الإسباني',
                  home: 'ريال مدريد',
                  away: 'برشلونة',
                  time: '18:15',
                  homeProbability: 40,
                  drawProbability: 30,
                  awayProbability: 30,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  final String title;
  final IconData leftIcon;
  final IconData rightIcon;
  final Key? titleKey;

  const _PageTitle({
    required this.title,
    required this.leftIcon,
    required this.rightIcon,
    this.titleKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(leftIcon, color: NukhbaaColors.secondary),
        const Spacer(),
        Text(
          title,
          key: titleKey,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        Icon(rightIcon, color: NukhbaaColors.secondary),
      ],
    );
  }
}

class _DateTabs extends StatelessWidget {
  const _DateTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab('لاحقًا', false),
          _tab('غدًا', false),
          _tab('اليوم', true),
        ],
      ),
    );
  }

  Widget _tab(String text, bool active) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? NukhbaaColors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? Colors.white : NukhbaaColors.secondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
// Prediction
/* -------------------------------------------------------------------------- */

class NukhbaaPredictionsPage extends StatefulWidget {
  const NukhbaaPredictionsPage({super.key});

  @override
  State<NukhbaaPredictionsPage> createState() => _NukhbaaPredictionsPageState();
}

class _NukhbaaPredictionsPageState extends State<NukhbaaPredictionsPage> {
  int homeScore = 2;
  int awayScore = 1;
  double confidence = .76;
  String result = '1';
  bool doublePrediction = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
        physics: const BouncingScrollPhysics(),
        children: [
          const _PageTitle(
            title: 'توقع النتيجة',
            leftIcon: Icons.arrow_back_rounded,
            rightIcon: Icons.info_outline_rounded,
          ),
          const SizedBox(height: 24),
          _matchHero(),
          const SizedBox(height: 24),
          const Text(
            'اختر النتيجة المتوقعة',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _scorePicker(),
          const SizedBox(height: 24),
          const Text(
            'النتيجة أو الغالبية',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _resultPicker(),
          const SizedBox(height: 24),
          _confidence(),
          const SizedBox(height: 22),
          _doubleOption(),
          const SizedBox(height: 18),
          _submitButton(),
        ],
      ),
    );
  }

  Widget _matchHero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NukhbaaColors.border),
      ),
      child: Column(
        children: [
          const Text(
            'الدوري الإنجليزي الممتاز',
            style: TextStyle(
              color: NukhbaaColors.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: const [
                    TeamLogo(name: 'ليفربول', icon: Icons.shield_rounded),
                    SizedBox(height: 8),
                    Text(
                      'ليفربول',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const Column(
                children: [
                  Text(
                    '20:30',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'اليوم',
                    style: TextStyle(
                      color: NukhbaaColors.secondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  children: const [
                    TeamLogo(name: 'أرسنال', icon: Icons.shield_rounded),
                    SizedBox(height: 8),
                    Text(
                      'أرسنال',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scorePicker() {
    return Row(
      children: [
        Expanded(
          child: _scoreControl(
            value: homeScore,
            onMinus: () {
              if (homeScore > 0) {
                setState(() => homeScore--);
              }
            },
            onPlus: () {
              if (homeScore < 20) {
                setState(() => homeScore++);
              }
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            ':',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(
          child: _scoreControl(
            value: awayScore,
            onMinus: () {
              if (awayScore > 0) {
                setState(() => awayScore--);
              }
            },
            onPlus: () {
              if (awayScore < 20) {
                setState(() => awayScore++);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _scoreControl({
    required int value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: NukhbaaColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NukhbaaColors.purple.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleButton(Icons.remove_rounded, onMinus),
          Text(
            '$value',
            style: const TextStyle(
              color: NukhbaaColors.purpleLight,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          _circleButton(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback callback) {
    return GestureDetector(
      onTap: callback,
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: NukhbaaColors.surface3,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 17, color: NukhbaaColors.secondary),
      ),
    );
  }

  Widget _resultPicker() {
    return Row(
      children: [
        _result('1', 'فوز أرسنال'),
        const SizedBox(width: 8),
        _result('X', 'تعادل'),
        const SizedBox(width: 8),
        _result('2', 'فوز ليفربول'),
      ],
    );
  }

  Widget _result(String value, String title) {
    final selected = result == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => result = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? NukhbaaColors.purple : NukhbaaColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? NukhbaaColors.purpleLight
                  : NukhbaaColors.border,
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
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white70 : NukhbaaColors.secondary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confidence() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'مستوى ثقتك',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            Text(
              '${(confidence * 100).round()}%',
              style: const TextStyle(
                color: NukhbaaColors.purpleLight,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Row(
          children: [
            Text(
              'منخفضة',
              style: TextStyle(color: NukhbaaColors.muted, fontSize: 10),
            ),
            Spacer(),
            Text(
              'متوسطة',
              style: TextStyle(color: NukhbaaColors.muted, fontSize: 10),
            ),
            Spacer(),
            Text(
              'عالية',
              style: TextStyle(color: NukhbaaColors.muted, fontSize: 10),
            ),
          ],
        ),
        Slider(
          value: confidence,
          onChanged: (value) {
            setState(() => confidence = value);
          },
        ),
        Text(
          'ثقتك: ${confidence >= .7
              ? 'عالية'
              : confidence >= .4
              ? 'متوسطة'
              : 'منخفضة'}',
          style: const TextStyle(color: NukhbaaColors.secondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _doubleOption() {
    return GestureDetector(
      onTap: () {
        setState(() => doublePrediction = !doublePrediction);
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: doublePrediction
              ? NukhbaaColors.gold.withValues(alpha: .08)
              : NukhbaaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: doublePrediction ? NukhbaaColors.gold : NukhbaaColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: NukhbaaColors.gold.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: NukhbaaColors.gold),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الدبل ×2',
                    style: TextStyle(
                      color: NukhbaaColors.gold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'ضاعف نقاطك إذا كان توقعك صحيحًا',
                    style: TextStyle(
                      color: NukhbaaColors.secondary,
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
                  ? NukhbaaColors.gold
                  : NukhbaaColors.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.bolt_rounded),
        label: const Text(
          'تأكيد التوقع',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: NukhbaaColors.purple,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
// Leaderboard
/* -------------------------------------------------------------------------- */

class NukhbaaLeaderboardPage extends StatelessWidget {
  const NukhbaaLeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
        physics: const BouncingScrollPhysics(),
        children: [
          const _PageTitle(
            title: 'المتصدرون',
            leftIcon: Icons.leaderboard_outlined,
            rightIcon: Icons.emoji_events_outlined,
          ),
          const SizedBox(height: 18),
          const _LeaderboardTabs(),
          const SizedBox(height: 24),
          const _Podium(),
          const SizedBox(height: 20),
          ...[
            ('4', 'خالد', '2,890'),
            ('5', 'يوسف', '2,750'),
            ('6', 'أنت', '2,480'),
            ('7', 'سلمان', '2,310'),
          ].map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RankRow(
                rank: e.$1,
                name: e.$2,
                points: e.$3,
                current: e.$2 == 'أنت',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTabs extends StatelessWidget {
  const _LeaderboardTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab('المجموعات', false),
          _tab('الأصدقاء', false),
          _tab('العالمي', true),
        ],
      ),
    );
  }

  Widget _tab(String text, bool active) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? NukhbaaColors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? Colors.white : NukhbaaColors.secondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 245,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _podiumPlayer(
              rank: '2',
              name: 'محمد',
              points: '3,110',
              height: 170,
              color: const Color(0xFFC0C0C0),
            ),
          ),
          Expanded(
            child: _podiumPlayer(
              rank: '1',
              name: 'أحمد',
              points: '3,240',
              height: 215,
              color: NukhbaaColors.gold,
            ),
          ),
          Expanded(
            child: _podiumPlayer(
              rank: '3',
              name: 'علي',
              points: '2,980',
              height: 150,
              color: const Color(0xFFCD7F32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _podiumPlayer({
    required String rank,
    required String name,
    required String points,
    required double height,
    required Color color,
  }) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NukhbaaColors.surface2,
              border: Border.all(color: color, width: 2),
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            '#$rank',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            name,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            points,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final String rank;
  final String name;
  final String points;
  final bool current;

  const _RankRow({
    required this.rank,
    required this.name,
    required this.points,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      decoration: BoxDecoration(
        color: current
            ? NukhbaaColors.purple.withValues(alpha: .14)
            : NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current ? NukhbaaColors.purple : NukhbaaColors.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              rank,
              style: TextStyle(
                color: current
                    ? NukhbaaColors.purpleLight
                    : NukhbaaColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: NukhbaaColors.surface3,
            ),
            child: const Icon(Icons.person_rounded, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(points, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
// Profile
/* -------------------------------------------------------------------------- */

class NukhbaaProfilePage extends StatelessWidget {
  final AuthenticatedUserDto user;
  final VoidCallback onSignOut;

  const NukhbaaProfilePage({
    required this.user,
    required this.onSignOut,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 110),
        children: [
          const _PageTitle(
            title: 'الحساب',
            titleKey: const Key('account.title'),
            leftIcon: Icons.settings_outlined,
            rightIcon: Icons.more_horiz_rounded,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              key: const Key('account.signOut'),
              tooltip: 'تسجيل الخروج',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [NukhbaaColors.gold, NukhbaaColors.purple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: NukhbaaColors.purple.withValues(alpha: .3),
                        blurRadius: 25,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person_rounded, size: 50),
                ),
                const SizedBox(height: 12),
                Text(
                  user.displayName,
                  key: const Key('account.displayName'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'متنبئ محترف',
                  style: TextStyle(color: NukhbaaColors.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            user.userId,
            key: const Key('account.userId'),
            style: const TextStyle(color: NukhbaaColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 25),
          const _ProfileStats(),
          const SizedBox(height: 20),
          _profileItem(
            Icons.admin_panel_settings_outlined,
            'لوحة تحكم المشرف',
            itemKey: const Key('account.adminDashboard'),
            onTap: user.role == 'admin'
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminHubScreen(),
                    ),
                  )
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('هذه اللوحة متاحة للمشرفين فقط'),
                    ),
                  ),
          ),
          _profileItem(Icons.emoji_events_outlined, 'إنجازاتي'),
          _profileItem(Icons.groups_outlined, 'مجموعاتي'),
          _profileItem(Icons.history_rounded, 'سجل التوقعات'),
          _profileItem(Icons.notifications_none_rounded, 'الإشعارات'),
          _profileItem(Icons.settings_outlined, 'الإعدادات'),
        ],
      ),
    );
  }

  Widget _profileItem(
    IconData icon,
    String title, {
    Key? itemKey,
    VoidCallback? onTap,
  }) {
    return Container(
      key: itemKey,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: NukhbaaColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: NukhbaaColors.purpleLight),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: NukhbaaColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NukhbaaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NukhbaaColors.border),
      ),
      child: const Row(
        children: [
          Expanded(
            child: _ProfileStat(value: '2,480', label: 'النقاط'),
          ),
          Expanded(
            child: _ProfileStat(value: '78%', label: 'الدقة'),
          ),
          Expanded(
            child: _ProfileStat(value: '126', label: 'الترتيب'),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;

  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: NukhbaaColors.purpleLight,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(color: NukhbaaColors.secondary, fontSize: 10),
        ),
      ],
    );
  }
}
