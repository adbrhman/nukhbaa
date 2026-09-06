#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""33_live_chip — شارة «مباشر» تومض وتصفّي فقط حين توجد مباراة جارية."""
import os, json, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
M = os.path.join(ROOT, "apps/mobile")
assert os.path.isdir(M), "apps/mobile not found under %s" % ROOT


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def patch(rel, old, new, count=1):
    p = os.path.join(M, rel)
    s = read(p)
    assert s.count(old) == count, "anchor x%d != %d in %s" % (s.count(old), count, rel)
    write(p, s.replace(old, new, count))
    print("patched", rel)


CHIP = r'''/// The "live" chip in the matches app bar. It pulses — and is tappable —
/// only while at least one fixture is actually in play; otherwise it sits
/// quiet and disabled rather than disappearing, so its absence is never
/// mistaken for a loading state.
///
/// "In play" is a **time estimate, not a server fact**: the feed carries a
/// kickoff instant and nothing else — no `live` / `finished` status — so
/// [liveWindow] below is the whole definition. Approved as option (أ) over
/// adding a real status field, which would have reached the contracts, the
/// routes and the database. If a status field ever lands, this constant and
/// [isFixtureLive] are the only two things that should change.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_motion.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// How long after kickoff a fixture is still treated as in play — a full
/// match plus half-time and stoppage, rounded up.
const Duration liveWindow = Duration(minutes: 120);

/// Whether a fixture kicking off at [kickoffAt] (an ISO-8601 instant, or
/// `null` when unscheduled) is in play right now.
bool isFixtureLive(String? kickoffAt) {
  if (kickoffAt == null) return false;
  final DateTime? kickoff = DateTime.tryParse(kickoffAt)?.toUtc();
  if (kickoff == null) return false;
  final DateTime now = DateTime.now().toUtc();
  if (!now.isAfter(kickoff)) return false;
  return now.difference(kickoff) < liveWindow;
}

/// The chip itself.
class LiveMatchesChip extends StatefulWidget {
  /// Creates the chip.
  const LiveMatchesChip({
    required this.hasLive,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// Whether any fixture is in play. Drives the pulse and the enabled state.
  final bool hasLive;

  /// Whether the live-only filter is currently on.
  final bool selected;

  /// Toggles the live-only filter.
  final VoidCallback onTap;

  @override
  State<LiveMatchesChip> createState() => _LiveMatchesChipState();
}

class _LiveMatchesChipState extends State<LiveMatchesChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.hasLive) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LiveMatchesChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasLive == oldWidget.hasLive) return;
    if (widget.hasLive) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bool enabled = widget.hasLive;
    final Color dotColor = enabled ? tokens.error : tokens.textMuted;
    final Color foreground = widget.selected
        ? tokens.onPrimary
        : enabled
        ? tokens.textPrimary
        : tokens.textMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: l10n.fixturesLiveLabel,
      child: GestureDetector(
        key: const Key('currentMonthFixtures.live'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: widget.selected
                ? tokens.primary
                : tokens.textPrimary.withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FadeTransition(
                // Never fades to nothing: the dot stays legible at its
                // dimmest, so the pulse reads as a heartbeat rather than
                // as the chip flickering in and out.
                opacity: Tween<double>(
                  begin: 0.35,
                  end: 1,
                ).animate(_pulse),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.fixturesLiveLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'''

write(os.path.join(M, "lib/features/fixture_prediction/widgets/live_matches_chip.dart"), CHIP)
print("created widgets/live_matches_chip.dart")

S = "lib/features/fixture_prediction/current_month_fixtures_screen.dart"

patch(
    S,
    "import 'widgets/fixtures_date_bar.dart';\nimport 'widgets/fotmob_match_card.dart';",
    "import 'widgets/fixtures_date_bar.dart';\nimport 'widgets/fotmob_match_card.dart';\n"
    "import 'widgets/live_matches_chip.dart';",
)

patch(
    S,
    """  DateTime _selectedDay = fixtureDayOnly(DateTime.now());
  bool _userPickedDay = false;""",
    """  DateTime _selectedDay = fixtureDayOnly(DateTime.now());
  bool _userPickedDay = false;

  /// Whether the live-only filter is on. Never trusted on its own — the
  /// build reads it as `_liveOnly && hasLive`, so a match finishing while
  /// the filter is on drops the screen back to the full day rather than
  /// stranding the user on an empty list they did not empty.
  bool _liveOnly = false;""",
)

patch(
    S,
    """  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = fixtureDayOnly(day);
      _userPickedDay = true;
    });
  }""",
    """  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = fixtureDayOnly(day);
      _userPickedDay = true;
      // Choosing a day is an explicit "show me this day" — keeping a live
      // filter on top of it would silently hide most of what was asked for.
      _liveOnly = false;
    });
  }

  /// Toggling the live filter on also moves the selection to today, since a
  /// fixture in play is by definition today's — without it the filter would
  /// read as broken while the strip sat on some other day.
  void _toggleLiveOnly() {
    setState(() {
      _liveOnly = !_liveOnly;
      if (_liveOnly) {
        _selectedDay = fixtureDayOnly(DateTime.now());
        _userPickedDay = true;
      }
    });
  }""",
)

patch(
    S,
    """    final DateTime day = _effectiveDay(feed.value ?? const []);
""",
    """    final List<CurrentMonthFixtureItemDto> all = feed.value ?? const [];
    final bool hasLive = all.any(
      (item) => isFixtureLive(item.fixture.kickoffAt),
    );
    final bool liveOnly = _liveOnly && hasLive;
    final DateTime day = liveOnly
        ? fixtureDayOnly(DateTime.now())
        : _effectiveDay(all);
""",
)

patch(
    S,
    """        actions: <Widget>[
          IconButton(""",
    """        actions: <Widget>[
          LiveMatchesChip(
            hasLive: hasLive,
            selected: liveOnly,
            onTap: _toggleLiveOnly,
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(""",
)

patch(
    S,
    """            final List<CurrentMonthFixtureItemDto> dayItems = items
                .where((item) {
                  final DateTime? kickoff = _kickoffDay(item);
                  return kickoff == null || isSameFixtureDay(kickoff, day);
                })
                .toList(growable: false);""",
    """            final List<CurrentMonthFixtureItemDto> dayItems = items
                .where((item) {
                  if (liveOnly) return isFixtureLive(item.fixture.kickoffAt);
                  final DateTime? kickoff = _kickoffDay(item);
                  return kickoff == null || isSameFixtureDay(kickoff, day);
                })
                .toList(growable: false);""",
)

# l10n
patch(
    "lib/l10n/app_ar.arb",
    '  "fixturesDayEmpty": "لا توجد مباريات في هذا اليوم."\n}',
    '  "fixturesDayEmpty": "لا توجد مباريات في هذا اليوم.",\n'
    '  "fixturesLiveLabel": "مباشر"\n}',
)
patch(
    "lib/l10n/app_en.arb",
    '  "fixturesDayEmpty": "No matches on this day."\n}',
    '  "fixturesDayEmpty": "No matches on this day.",\n'
    '  "fixturesLiveLabel": "Live"\n}',
)
patch(
    "lib/l10n/app_localizations.dart",
    "  String get fixturesDayEmpty;\n}",
    "  String get fixturesDayEmpty;\n\n"
    "  /// No description provided for @fixturesLiveLabel.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'Live'**\n"
    "  String get fixturesLiveLabel;\n}",
)
patch(
    "lib/l10n/app_localizations_ar.dart",
    "  String get fixturesDayEmpty => 'لا توجد مباريات في هذا اليوم.';\n}",
    "  String get fixturesDayEmpty => 'لا توجد مباريات في هذا اليوم.';\n\n"
    "  @override\n  String get fixturesLiveLabel => 'مباشر';\n}",
)
patch(
    "lib/l10n/app_localizations_en.dart",
    "  String get fixturesDayEmpty => 'No matches on this day.';\n}",
    "  String get fixturesDayEmpty => 'No matches on this day.';\n\n"
    "  @override\n  String get fixturesLiveLabel => 'Live';\n}",
)

for arb in ("lib/l10n/app_ar.arb", "lib/l10n/app_en.arb"):
    json.loads(read(os.path.join(M, arb)))
print("ARB files still parse as JSON")

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 33_live_chip: شارة «مباشر» في شريط شاشة المباريات. "
    "«جارية» تقدير زمني محلي لا حقيقة من الخادم — التغذية تحمل kickoffAt "
    "ولا تحمل حالة — فـliveWindow = ١٢٠ دقيقة بعد الانطلاق هي التعريف "
    "كاملًا (الخيار «أ» بقرار المالك، مقابل إضافة حقل حالة يمسّ العقود "
    "والمسارات وقاعدة البيانات). الشارة تنبض وتقبل النقر فقط حين توجد "
    "مباراة جارية، وتبقى ظاهرة خافتة معطَّلة فيما عدا ذلك كي لا يُقرأ "
    "غيابها كتحميل. النبضة لا تصل إلى صفر (0.35..1) فتبدو نبضًا لا وميضًا "
    "مكسورًا. حارسان ضدّ الحالات العالقة: البناء يقرأ _liveOnly && hasLive "
    "فتنتهي التصفية تلقائيًا حين تنتهي آخر مباراة بدل ترك المستخدم أمام "
    "قائمة فارغة لم يُفرغها، واختيار يوم يُطفئ التصفية صراحةً؛ وتشغيلها "
    "ينقل التحديد إلى اليوم لأن الجارية اليوم بالضرورة. مفتاح ARB واحد "
    "جديد مع التوليد اليدوي — "
    "apps/mobile/lib/features/fixture_prediction/widgets/live_matches_chip.dart, "
    "apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart, "
    "apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, "
    "apps/mobile/lib/l10n/app_localizations.dart, "
    "apps/mobile/lib/l10n/app_localizations_ar.dart, "
    "apps/mobile/lib/l10n/app_localizations_en.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    "apps/mobile/lib/features/fixture_prediction/widgets/live_matches_chip.dart",
    "apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart",
    "apps/mobile/lib/l10n/app_ar.arb",
    "apps/mobile/lib/l10n/app_en.arb",
    "apps/mobile/lib/l10n/app_localizations.dart",
    "apps/mobile/lib/l10n/app_localizations_ar.dart",
    "apps/mobile/lib/l10n/app_localizations_en.dart",
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "feat(mobile): live chip that pulses and filters only while a fixture is in play"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
