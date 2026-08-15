/// The reusable Fotmob-style dark match card: a color-bled crest header, a
/// team-vs-team row with +/?/− goal steppers, and a neon "Double" star pill
/// (already replaces any win-probability display — there never was one here).
///
/// Extracted out of `prediction_screen.dart` so the unified matches feed
/// (`../matches/matches_feed_screen.dart`) renders fixtures with the exact
/// same card instead of a second, duplicated implementation. Every widget
/// `Key` is unchanged from the original — existing prediction-screen tests
/// keep passing.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../competition/team_registry.dart';

// ─────────────────────────────────────────────────────────────────────────
// Design tokens (mirrors the CSS variables from the original design report).
// ─────────────────────────────────────────────────────────────────────────
class MatchCardTokens {
  static const Color bgPage = Color(0xFF0A0A0A);
  static const Color cardGradStart = Color(0xE6281E1E); // rgba(40,30,30,.9)
  static const Color cardGradEnd = Color(0xE61C2028); // rgba(28,32,40,.9)

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textTertiary = Color(0xFF6E6E73);

  static const Color btnBg = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const Color btnBorder = Color(0x14FFFFFF); // rgba(255,255,255,.08)

  static const Color doubleInactiveBg = Color(0x0FFFFFFF);
  static const Color doubleActiveBg = Color(0x26FFD700); // rgba(255,215,0,.15)
  static const Color doubleGlow = Color(0xFFFFD700);

  static const double cardRadius = 16;
  static const double logoSize = 48;
}

/// A small palette to derive a stable "team color" from a team name, used for
/// both the round logo initials and the color-bleed glow (no logo assets exist
/// in the DTO — team names + kickoff are the only fixture identity available).
Color teamColorFor(String? name) {
  if (name == null || name.isEmpty) return const Color(0xFF3A3A3C);
  const palette = <Color>[
    Color(0xFFE30613), // red
    Color(0xFF1D428A), // blue
    Color(0xFFF5A12D), // orange
    Color(0xFF132257), // navy
    Color(0xFF78D0F1), // light blue
    Color(0xFF2E7D32), // green
    Color(0xFF6A1B9A), // purple
    Color(0xFF00897B), // teal
    Color(0xFFC2185B), // pink
    Color(0xFFEF6C00), // deep orange
  ];
  var hash = 0;
  for (final code in name.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

/// A single fixture's predict card: crest glow, team columns, +/?/− goal
/// steppers, and the Double star pill.
///
/// [leagueLabel] is the header text shown before the kickoff time (e.g. a
/// competition's display name, or a generic "Fixtures" title) — callers own
/// what that string is; this widget only formats it with the kickoff.
class MatchCard extends StatelessWidget {
  const MatchCard({
    required this.leagueLabel,
    required this.fixture,
    required this.locked,
    required this.homeController,
    required this.awayController,
    required this.enabled,
    required this.isDouble,
    required this.doubleSelectable,
    required this.onDoubleSelected,
    required this.onChanged,
    required this.doubleLabel,
    required this.lockedLabel,
    super.key,
  });

  final String leagueLabel;
  final RoundFixtureCardDto fixture;
  final bool locked;
  final TextEditingController homeController;
  final TextEditingController awayController;
  final bool enabled;
  final bool isDouble;
  final bool doubleSelectable;
  final VoidCallback onDoubleSelected;
  final VoidCallback onChanged;
  final String doubleLabel;
  final String lockedLabel;

  String _kickoffLabel() {
    final k = fixture.kickoffAt;
    if (k == null) return '';
    final dt = DateTime.tryParse(k)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the known brand's primary color; fall back to a stable
    // name-derived color when the team isn't in the local registry yet.
    final homeBrand = lookupTeam(fixture.homeTeam);
    final awayBrand = lookupTeam(fixture.awayTeam);
    final homeColor = homeBrand?.c1 ?? teamColorFor(fixture.homeTeam);
    final awayColor = awayBrand?.c1 ?? teamColorFor(fixture.awayTeam);
    final home = fixture.homeTeam ?? '?';
    final away = fixture.awayTeam ?? '?';
    final kickoff = _kickoffLabel();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MatchCardTokens.cardRadius),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [MatchCardTokens.cardGradStart, MatchCardTokens.cardGradEnd],
        ),
      ),
      child: Stack(
        children: <Widget>[
          // Color-bleed glow, left (home). Purely decorative — must never
          // intercept touches meant for the score fields stacked above it.
          Positioned(
            left: -30,
            top: 0,
            bottom: 0,
            child: IgnorePointer(child: GlowBlob(color: homeColor)),
          ),
          // Color-bleed glow, right (away). Same rationale as above.
          Positioned(
            right: -30,
            top: 0,
            bottom: 0,
            child: IgnorePointer(child: GlowBlob(color: awayColor)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                // Header: league line + external icon placeholder.
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.sports_soccer,
                      size: 16,
                      color: MatchCardTokens.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kickoff.isEmpty
                            ? leagueLabel
                            : '$leagueLabel • $kickoff',
                        style: const TextStyle(
                          color: MatchCardTokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (locked)
                      const Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: MatchCardTokens.textTertiary,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Body: home team | predict controls | away team.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: TeamColumn(name: home, color: homeColor),
                    ),
                    const SizedBox(width: 8),
                    PredictCenter(
                      fixtureId: fixture.fixtureId,
                      homeController: homeController,
                      awayController: awayController,
                      enabled: enabled && !locked,
                      isDouble: isDouble,
                      doubleSelectable: doubleSelectable,
                      onDoubleSelected: onDoubleSelected,
                      onChanged: onChanged,
                      doubleLabel: doubleLabel,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TeamColumn(name: away, color: awayColor),
                    ),
                  ],
                ),
                if (locked) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    lockedLabel,
                    key: Key('prediction.locked.${fixture.fixtureId}'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: MatchCardTokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft, blurred circular color blob (the CSS ::before/::after color bleed).
class GlowBlob extends StatelessWidget {
  const GlowBlob({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// A team column: a real crest (when the team is recognized) or a colored
/// circular initials badge, plus the display name — Arabic when the team is
/// recognized, otherwise the raw server value, otherwise "؟".
class TeamColumn extends StatelessWidget {
  const TeamColumn({required this.name, required this.color, super.key});

  /// The English team name from the DTO (`'?'` when the server sent `null`).
  final String name;

  /// The fallback badge color, used only when no brand is recognized.
  final Color color;

  TeamBrand? get _brand => name == '?' ? null : lookupTeam(name);

  String get _displayName {
    final brand = _brand;
    if (brand != null) return brand.ar;
    return name == '?' ? '؟' : name;
  }

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '?') return '؟';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final first = parts.first;
      return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  Widget _initialsBadge() => Text(
    _initials,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 16,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final brand = _brand;
    return Column(
      children: <Widget>[
        Container(
          width: MatchCardTokens.logoSize,
          height: MatchCardTokens.logoSize,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (brand?.c1 ?? color).withValues(alpha: 0.9),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: brand == null
              ? _initialsBadge()
              : Image.network(
                  brand.logoUrl,
                  width: MatchCardTokens.logoSize,
                  height: MatchCardTokens.logoSize,
                  fit: BoxFit.contain,
                  // A recognized team whose crest fails to load (offline,
                  // CDN hiccup) still gets a clean badge — never a broken
                  // image icon.
                  errorBuilder: (context, error, stackTrace) =>
                      _initialsBadge(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : _initialsBadge(),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          _displayName,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: MatchCardTokens.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The center predict area: two stepper columns (home / away) + Double pill.
class PredictCenter extends StatelessWidget {
  const PredictCenter({
    required this.fixtureId,
    required this.homeController,
    required this.awayController,
    required this.enabled,
    required this.isDouble,
    required this.doubleSelectable,
    required this.onDoubleSelected,
    required this.onChanged,
    required this.doubleLabel,
    super.key,
  });

  final String fixtureId;
  final TextEditingController homeController;
  final TextEditingController awayController;
  final bool enabled;
  final bool isDouble;
  final bool doubleSelectable;
  final VoidCallback onDoubleSelected;
  final VoidCallback onChanged;
  final String doubleLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GoalStepper(
              key: Key('prediction.home.$fixtureId'),
              controller: homeController,
              enabled: enabled,
              onChanged: onChanged,
            ),
            const SizedBox(width: 4),
            GoalStepper(
              key: Key('prediction.away.$fixtureId'),
              controller: awayController,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ],
        ),
        const SizedBox(height: 8),
        DoubleButton(
          buttonKey: Key('prediction.double.$fixtureId'),
          active: isDouble,
          enabled: doubleSelectable,
          label: doubleLabel,
          onPressed: doubleSelectable ? onDoubleSelected : null,
        ),
      ],
    );
  }
}

/// One team's +/?/− stepper column. The center shows the current goal count
/// (or "?" when empty); the field is still directly editable via a hidden tap.
class GoalStepper extends StatelessWidget {
  const GoalStepper({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  int get _value => int.tryParse(controller.text.trim()) ?? 0;
  bool get _hasValue => controller.text.trim().isNotEmpty;

  void _bump(int delta) {
    final next = (_value + delta).clamp(0, 99);
    controller.text = '$next';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Matches the widened CenterField (52) so the stepper column doesn't
      // clip it.
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StepBtn(icon: Icons.add, enabled: enabled, onTap: () => _bump(1)),
          const SizedBox(height: 4),
          CenterField(
            controller: controller,
            enabled: enabled,
            placeholder: _hasValue ? null : '?',
            onChanged: onChanged,
          ),
          const SizedBox(height: 4),
          StepBtn(icon: Icons.remove, enabled: enabled, onTap: () => _bump(-1)),
        ],
      ),
    );
  }
}

/// A single +/− button in the stepper.
class StepBtn extends StatelessWidget {
  const StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MatchCardTokens.btnBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: MatchCardTokens.btnBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 44,
          height: 28,
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? MatchCardTokens.textSecondary
                : MatchCardTokens.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// The editable center goal field (shows "?" when empty, like Fotmob).
class CenterField extends StatelessWidget {
  const CenterField({
    required this.controller,
    required this.enabled,
    required this.placeholder,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? placeholder;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Wider than the original 44x32 hit target — the field was too
      // narrow to register taps reliably on real devices.
      width: 52,
      height: 40,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        cursorColor: MatchCardTokens.textPrimary,
        // Dismiss the keyboard on an outside tap instead of trapping focus.
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        style: const TextStyle(
          color: MatchCardTokens.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          filled: true,
          fillColor: MatchCardTokens.btnBg,
          contentPadding: EdgeInsets.zero,
          hintText: placeholder,
          hintStyle: const TextStyle(
            color: MatchCardTokens.textSecondary,
            fontSize: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: MatchCardTokens.btnBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white70),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: MatchCardTokens.btnBorder),
          ),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// The neon "Double" pill under the predict controls.
///
/// Its tappable core is an [IconButton] carrying [buttonKey] so
/// `tester.widget<IconButton>(find.byKey(...))` in existing tests keeps
/// working; the pill chrome (glow + label) wraps it visually.
class DoubleButton extends StatelessWidget {
  const DoubleButton({
    required this.active,
    required this.enabled,
    required this.label,
    required this.onPressed,
    required this.buttonKey,
    super.key,
  });

  final bool active;
  final bool enabled;
  final String label;
  final VoidCallback? onPressed;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 30,
      decoration: BoxDecoration(
        color: active
            ? MatchCardTokens.doubleActiveBg
            : MatchCardTokens.doubleInactiveBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: active
            ? [
                BoxShadow(
                  color: MatchCardTokens.doubleGlow.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: IconButton(
        key: buttonKey,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        constraints: const BoxConstraints(minWidth: 0, minHeight: 30),
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              active ? Icons.star : Icons.star_border,
              size: 14,
              color: active
                  ? MatchCardTokens.doubleGlow
                  : MatchCardTokens.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active
                    ? MatchCardTokens.doubleGlow
                    : MatchCardTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
