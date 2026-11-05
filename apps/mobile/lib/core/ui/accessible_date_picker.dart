/// The `builder` every `showDatePicker` of the app passes (script 214).
///
/// The Material date dialog is 328 dp wide, so its seven day columns are
/// 46.9 dp: under the 48 dp a touch target needs (Accessibility Scanner,
/// 2026-11-05, every day cell). The dialog scales its size with the text
/// scale, so a text scale of at least [minTextScale] around it widens the
/// cells to 48 dp or more, and a reader whose own scale is larger keeps it.
library;

import 'package:flutter/material.dart';

/// The least text scale the date dialog is drawn at: 328 x 1.06 / 7 = 49.7 dp
/// a day column.
const double minDatePickerTextScale = 1.06;

/// A `showDatePicker` `builder`: draws [child] (the dialog) at no less than
/// [minDatePickerTextScale].
Widget accessibleDatePickerBuilder(BuildContext context, Widget? child) {
  final Widget dialog = child ?? const SizedBox.shrink();
  final MediaQueryData media = MediaQuery.of(context);
  if (media.textScaler.scale(1) >= minDatePickerTextScale) return dialog;
  return MediaQuery(
    data: media.copyWith(
      textScaler: const TextScaler.linear(minDatePickerTextScale),
    ),
    child: dialog,
  );
}
