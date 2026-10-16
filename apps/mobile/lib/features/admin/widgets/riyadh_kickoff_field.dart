/// The kickoff of a fixture, picked and shown on Riyadh's clock (audit
/// L-12), for the add and edit forms alike: the button reads the Riyadh
/// time, and the line under it says so, with the phone's own time beside it
/// when the phone is on another zone.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/time/riyadh_clock.dart';
import 'admin_ui_kit.dart';

/// The kickoff button and its zone line.
class RiyadhKickoffField extends StatelessWidget {
  /// Creates the field.
  const RiyadhKickoffField({
    super.key,
    required this.buttonKey,
    required this.value,
    required this.emptyLabel,
    required this.enabled,
    required this.onPicked,
  });

  /// The button's key (the forms' existing `...kickoffPicker` keys).
  final Key buttonKey;

  /// The kickoff instant, or null before one is picked.
  final DateTime? value;

  /// The button's words before a kickoff is picked.
  final String emptyLabel;

  /// Whether the button may be pressed.
  final bool enabled;

  /// Called with the picked instant (UTC).
  final ValueChanged<DateTime> onPicked;

  /// What the line under the button says for [value].
  static String zoneLine(DateTime? value) {
    if (value == null) return 'أدخل الموعد بتوقيت الرياض';
    final String? device = RiyadhClock.deviceLabel(value);
    return device == null ? 'بتوقيت الرياض' : 'بتوقيت الرياض — $device';
  }

  Future<void> _pick(BuildContext context) async {
    final DateTime wall = RiyadhClock.wallOf(value ?? DateTime.now());
    final DateTime today = RiyadhClock.wallOf(DateTime.now());
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime(wall.year, wall.month, wall.day),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2),
    );
    if (date == null || !context.mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: wall.hour, minute: wall.minute),
    );
    if (time == null || !context.mounted) return;
    onPicked(
      RiyadhClock.instantOf(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? picked = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AdminSecondaryButton(
          key: buttonKey,
          label: picked == null ? emptyLabel : RiyadhClock.stamp(picked),
          icon: Icons.event_outlined,
          onPressed: enabled ? () => _pick(context) : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          zoneLine(picked),
          key: const Key('admin.kickoff.zone'),
          style: context.text.bodySmall?.copyWith(
            color: context.tokens.textMuted,
          ),
        ),
      ],
    );
  }
}
