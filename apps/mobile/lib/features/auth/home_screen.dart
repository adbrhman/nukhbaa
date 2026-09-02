import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/match_card.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.user,
    required this.onOpenMatches,
    required this.onOpenPredictions,
    required this.onOpenLeaderboards,
    required this.onOpenAccount,
    super.key,
  });

  final AuthenticatedUserDto user;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenPredictions;
  final VoidCallback onOpenLeaderboards;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final fixtures = ref.watch(currentMonthFixturesProvider);
    final seasons = ref.watch(activeSeasonsProvider);
    final l10n = AppLocalizations.of(context);
    final name = user.displayName.trim().isEmpty ? 'المتنبئ' : user.displayName;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(currentMonthFixturesProvider);
            ref.invalidate(activeSeasonsProvider);
            try { await ref.read(currentMonthFixturesProvider.future); } on Object { }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 112),
            children: <Widget>[
              _Header(onNotifications: onOpenAccount, onAccount: onOpenAccount),
              const SizedBox(height: 26),
              Text('مرحبًا، $name', key: const Key('home.welcome'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text('جاهز تثبت أنك من النخبة؟', style: TextStyle(color: tokens.textSecondary, fontSize: 14)),
              const SizedBox(height: 20),
              _HeroCard(onTap: onOpenMatches),
              const SizedBox(height: 22),
              _SectionHeader(title: 'ملخصك هذا الموسم', action: 'الترتيب', onAction: onOpenLeaderboards),
              const SizedBox(height: 10),
              _StatsRow(seasons: seasons),
              const SizedBox(height: 24),
              _SectionHeader(title: l10n.matchesTitle, action: 'عرض الكل', onAction: onOpenMatches),
              const SizedBox(height: 10),
              fixtures.when(
                loading: () => const _LoadingCard(),
                error: (error, stack) => _MessageCard(message: 'تعذر تحميل مبارياتك الآن.', actionLabel: 'إعادة المحاولة', onTap: onOpenMatches),
                data: (items) => items.isEmpty
                    ? _MessageCard(message: l10n.matchesEmpty, actionLabel: 'فتح المباريات', onTap: onOpenMatches)
                    : Column(children: items.take(3).map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: MatchCard(competition: item.competitionName, homeTeam: item.fixture.homeTeam, awayTeam: item.fixture.awayTeam, kickoffAt: item.fixture.kickoffAt, onTap: onOpenMatches))).toList()),
              ),
              const SizedBox(height: 14),
              _QuickLinks(onMatches: onOpenMatches, onPredictions: onOpenPredictions, onLeaderboard: onOpenLeaderboards, onAccount: onOpenAccount),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNotifications, required this.onAccount});
  final VoidCallback onNotifications;
  final VoidCallback onAccount;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(children: <Widget>[
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('نُخبة', style: TextStyle(color: t.textPrimary, fontSize: 24, fontWeight: FontWeight.w900)),
        Text('FOOTBALL PREDICTIONS', style: TextStyle(color: t.primaryLight, fontSize: 8, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
      ]),
      const Spacer(),
      _IconButton(icon: Icons.notifications_none_rounded, onTap: onNotifications),
      const SizedBox(width: 8),
      _IconButton(icon: Icons.person_outline_rounded, onTap: onAccount),
    ]);
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon; final VoidCallback onTap;
  @override Widget build(BuildContext context) => Material(color: context.tokens.surfaceElevated, borderRadius: AppRadius.brMd, child: InkWell(onTap: onTap, borderRadius: AppRadius.brMd, child: Padding(padding: const EdgeInsets.all(11), child: Icon(icon, size: 20, color: context.tokens.textSecondary))));
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: t.primaryGradient, borderRadius: const BorderRadius.all(Radius.circular(24)), boxShadow: t.shadowMd), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[Container(width: 8, height: 8, decoration: BoxDecoration(color: t.gold, shape: BoxShape.circle)), const SizedBox(width: 8), Text('المباراة القادمة', style: TextStyle(color: t.onPrimary.withValues(alpha: .82), fontSize: 12, fontWeight: FontWeight.w700)), const Spacer(), Text('التوقع مفتوح', style: TextStyle(color: t.onPrimary, fontSize: 11, fontWeight: FontWeight.w800))]),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[_Team(name: 'الفريق المضيف', icon: Icons.shield_rounded), Text('VS', style: TextStyle(color: t.onPrimary.withValues(alpha: .7), fontWeight: FontWeight.w900)), _Team(name: 'الفريق الضيف', icon: Icons.shield_outlined)]),
      const SizedBox(height: 20),
      Row(children: <Widget>[Icon(Icons.schedule_rounded, size: 16, color: t.onPrimary.withValues(alpha: .8)), const SizedBox(width: 6), Text('اليوم • 21:00', style: TextStyle(color: t.onPrimary.withValues(alpha: .9), fontSize: 12)), const Spacer(), FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: t.onPrimary, foregroundColor: t.primary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)), child: const Text('توقّع الآن'))]),
    ]));
  }
}

class _Team extends StatelessWidget { const _Team({required this.name, required this.icon}); final String name; final IconData icon; @override Widget build(BuildContext context) { final t=context.tokens; return Column(children:<Widget>[Container(width:48,height:48,decoration:BoxDecoration(color:t.onPrimary.withValues(alpha:.14),shape:BoxShape.circle),child:Icon(icon,color:t.onPrimary,size:28)),const SizedBox(height:8),SizedBox(width: ninety, child: Text(name,textAlign:TextAlign.center,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:t.onPrimary,fontSize:11,fontWeight:FontWeight.w700)))]); } }

const double ninety = 90;

class _StatsRow extends StatelessWidget { const _StatsRow({required this.seasons}); final AsyncValue<List<ActiveSeasonDto>> seasons; @override Widget build(BuildContext context) { final seasonCount=seasons.valueOrNull?.length; return Row(children:<Widget>[_Stat(label:'النقاط',value:'—',icon:Icons.stars_rounded),const SizedBox(width:8),_Stat(label:'مركزي',value:'—',icon:Icons.emoji_events_rounded),const SizedBox(width:8),_Stat(label:'المواسم',value:seasonCount?.toString() ?? '…',icon:Icons.flag_rounded)]); } }
class _Stat extends StatelessWidget { const _Stat({required this.label,required this.value,required this.icon}); final String label,value; final IconData icon; @override Widget build(BuildContext context){final t=context.tokens;return Expanded(child:Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:t.surface,borderRadius:AppRadius.brMd,border:Border.all(color:t.border)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:<Widget>[Icon(icon,color:t.gold,size:19),const SizedBox(height:8),Text(value,style:TextStyle(color:t.textPrimary,fontSize:18,fontWeight:FontWeight.w900)),Text(label,style:TextStyle(color:t.textSecondary,fontSize:10))])));}}

class _QuickLinks extends StatelessWidget { const _QuickLinks({required this.onMatches,required this.onPredictions,required this.onLeaderboard,required this.onAccount}); final VoidCallback onMatches,onPredictions,onLeaderboard,onAccount; @override Widget build(BuildContext context)=>Row(children:<Widget>[_Link(icon:Icons.sports_soccer_rounded,label:'المباريات',onTap:onMatches),_Link(icon:Icons.bolt_rounded,label:'توقعاتي',onTap:onPredictions),_Link(icon:Icons.leaderboard_rounded,label:'الترتيب',onTap:onLeaderboard),_Link(icon:Icons.settings_rounded,label:'الإعدادات',onTap:onAccount)]); }
class _Link extends StatelessWidget { const _Link({required this.icon,required this.label,required this.onTap}); final IconData icon; final String label; final VoidCallback onTap; @override Widget build(BuildContext context)=>Expanded(child:InkWell(onTap:onTap,borderRadius:AppRadius.brMd,child:Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Column(children:<Widget>[Icon(icon,color:context.tokens.primaryLight,size:20),const SizedBox(height:5),Text(label,style:TextStyle(color:context.tokens.textSecondary,fontSize:10,fontWeight:FontWeight.w700))])))); }

class _SectionHeader extends StatelessWidget { const _SectionHeader({required this.title,required this.action,required this.onAction}); final String title,action; final VoidCallback onAction; @override Widget build(BuildContext context)=>Row(children:<Widget>[Text(title,style:TextStyle(color:context.tokens.textPrimary,fontSize:16,fontWeight:FontWeight.w900)),const Spacer(),TextButton(onPressed:onAction,child:Text(action))]); }
class _LoadingCard extends StatelessWidget { const _LoadingCard(); @override Widget build(BuildContext context)=>Container(height:112,decoration:BoxDecoration(color:context.tokens.surfaceElevated,borderRadius:AppRadius.brMd),child:Center(child:CircularProgressIndicator(color:context.tokens.primaryLight))); }
class _MessageCard extends StatelessWidget { const _MessageCard({required this.message,required this.actionLabel,required this.onTap}); final String message,actionLabel; final VoidCallback onTap; @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(AppSpacing.md),decoration:BoxDecoration(color:context.tokens.surfaceElevated,borderRadius:AppRadius.brMd,border:Border.all(color:context.tokens.border)),child:Row(children:<Widget>[Expanded(child:Text(message,style:TextStyle(color:context.tokens.textSecondary))),TextButton(onPressed:onTap,child:Text(actionLabel))])); }
