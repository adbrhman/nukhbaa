/// The head-to-head league tab (دوري المواجهات, migration 0100).
///
/// Everything drawn here is the server's: the state of the month, each
/// round's phase (`open` for the next one), its opponent, points and result,
/// the table's order and numbers, the two zones and the days left
/// (`GET /me/h2h-league`). The client names them and nothing else -- it
/// never sorts, sums or decides a result (Axioms 2/5). The device clock
/// only counts down to a kickoff the server sent.
///
/// Before the caller holds a seat (the league has not opened, the draw is
/// still to come, or they are outside it) the tab explains why and lists
/// the rules. Once seated it shows the division card, then one of three
/// sections: the match that matters now, the group's table, and the rounds.
/// The rules are one tap away in the header.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_tab_header.dart';
import '../../core/ui/segmented_pills.dart';
import '../competition/widgets/async_list_view.dart';
import 'h2h_providers.dart';
import 'h2h_texts.dart';
import 'widgets/h2h_division_card.dart';
import 'widgets/h2h_next_match.dart';
import 'widgets/h2h_rounds.dart';
import 'widgets/h2h_table.dart';

/// The المواجهات tab.
class H2hScreen extends ConsumerStatefulWidget {
  /// Creates the tab.
  const H2hScreen({
    this.onOpenMatches,
    this.now,
    this.initialSection = 0,
    super.key,
  });

  /// Opens the matches tab (the shell's), where a round's fixtures are
  /// predicted. Null hides the button.
  final VoidCallback? onOpenMatches;

  /// The clock the countdown reads; the device's when null.
  final DateTime Function()? now;

  /// The section a seated month opens on: 0 the match, 1 the table, 2 the
  /// rounds.
  final int initialSection;

  @override
  ConsumerState<H2hScreen> createState() => _H2hScreenState();
}

class _H2hScreenState extends ConsumerState<H2hScreen> {
  late int _section = widget.initialSection.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The tab's name at the start, like every tab (UI-20).
      appBar: AppTabHeader(
        title: const Text(h2hTitle, key: Key('h2h.title')),
        actions: <Widget>[
          IconButton(
            key: const Key('h2h.rulesButton'),
            tooltip: 'كيف يعمل الدوري؟',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => showH2hRules(context),
          ),
        ],
      ),
      // The shell's bottom bar floats over the page (`extendBody`), so the
      // list stops above it -- the same SafeArea the other tabs use.
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myH2hLeagueProvider);
            try {
              await ref.read(myH2hLeagueProvider.future);
            } on Object {
              // The failure shows through the page; the pull still ends.
            }
          },
          child: AsyncObjectView<MyH2hLeagueDto>(
            value: ref.watch(myH2hLeagueProvider),
            onRetry: () => ref.invalidate(myH2hLeagueProvider),
            builder: (BuildContext context, MyH2hLeagueDto league) => ListView(
              key: const Key('h2h.list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                104,
              ),
              children: league.state == 'open'
                  ? _openMonth(league)
                  : _waiting(league),
            ),
          ),
        ),
      ),
    );
  }

  /// A month without a seat for the caller: why, then the rules.
  List<Widget> _waiting(MyH2hLeagueDto league) => <Widget>[
    _StateCard(league: league),
    const SizedBox(height: AppSpacing.lg),
    const AppCard(key: Key('h2h.rules'), child: H2hRulesList(withTitle: true)),
  ];

  /// The caller's seated month: the card, the three sections, the one
  /// chosen.
  List<Widget> _openMonth(MyH2hLeagueDto league) => <Widget>[
    H2hDivisionCard(league: league),
    const SizedBox(height: AppSpacing.md),
    SegmentedPills(
      key: const Key('h2h.sections'),
      labels: h2hSectionLabels,
      selectedIndex: _section,
      keyPrefix: 'h2h.section',
      onSelected: (int index) => setState(() => _section = index),
    ),
    const SizedBox(height: AppSpacing.lg),
    switch (_section) {
      0 => H2hNextMatch(
        league: league,
        now: widget.now ?? DateTime.now,
        onOpenMatches: widget.onOpenMatches,
      ),
      1 => H2hTable(league: league),
      _ => H2hRoundsList(league: league),
    },
  ];
}

/// Opens the rules as a sheet over the tab.
Future<void> showH2hRules(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: AppBreakpoints.tablet),
    builder: (BuildContext context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: const SingleChildScrollView(
          key: Key('h2h.rulesSheet'),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: H2hRulesList(withTitle: true),
        ),
      ),
    ),
  );
}

/// Why the caller has no seat this month.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.league});

  final MyH2hLeagueDto league;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final ({String title, String body}) message = h2hStateMessage(
      league.state,
      league.startsOn,
    );
    return AppCard(
      key: Key('h2h.state.${league.state}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.shield_rounded, color: t.gold, size: 28),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  h2hLeagueName,
                  style: context.text.titleMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message.title,
            key: const Key('h2h.state.title'),
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message.body,
            style: context.text.bodyMedium?.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The rules, numbered.
class H2hRulesList extends StatelessWidget {
  /// Creates the list, under its title when [withTitle].
  const H2hRulesList({this.withTitle = false, super.key});

  /// Whether the list carries its own title.
  final bool withTitle;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (withTitle)
          Text(
            'كيف يعمل الدوري؟',
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        for (int i = 0; i < h2hRules.length; i++) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Row(
            key: Key('h2h.rule.${i + 1}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${i + 1}.',
                style: context.text.bodyMedium?.copyWith(
                  color: t.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  h2hRules[i],
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
