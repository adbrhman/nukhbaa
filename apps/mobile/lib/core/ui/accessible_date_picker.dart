/// The `builder` every `showDatePicker` of the app passes (script 214).
///
/// The Material 3 date dialog is 360 dp wide, and its day grid is padded 12
/// dp each side, so on a 384 dp phone the default 16 dp margin cut it to 352
/// dp and every day column to 46.9 dp: under the 48 dp a touch target needs
/// (Accessibility Scanner, 2026-11-05, every day cell). The dialog scales
/// its size with the text scale, so a text scale of at least
/// [minDatePickerTextScale] around it widens it to 381.6 dp, and
/// [showAccessibleDatePicker] shrinks the side margin so the screen can hold
/// that width (script 215; 214 raised the scale alone, which the margin
/// cancelled). A reader whose own scale is larger keeps it.
library;

import 'package:flutter/material.dart';

/// The least text scale the date dialog is drawn at: (360 x 1.06 - 24) / 7 =
/// 51.1 dp a day column, 48.0 dp on a 360 dp phone.
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

/// The date dialog's width at [minDatePickerTextScale].
const double datePickerDialogWidth = 360 * minDatePickerTextScale;

/// The side margin that lets a [screenWidth] hold the dialog: the default
/// 16 dp when there is room, less (down to none) when there is not.
double datePickerSideMargin(double screenWidth) {
  final double room = (screenWidth - datePickerDialogWidth) / 2;
  return room.clamp(0.0, 16.0).toDouble();
}

/// `showDatePicker` for the app: the dialog drawn by
/// [accessibleDatePickerBuilder] in the margin [datePickerSideMargin] leaves.
Future<DateTime?> showAccessibleDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final double margin = datePickerSideMargin(MediaQuery.sizeOf(context).width);
  return showDialog<DateTime>(
    context: context,
    builder: (BuildContext dialogContext) => accessibleDatePickerBuilder(
      dialogContext,
      DatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        insetPadding: EdgeInsets.symmetric(horizontal: margin, vertical: 24),
      ),
    ),
  );
}
