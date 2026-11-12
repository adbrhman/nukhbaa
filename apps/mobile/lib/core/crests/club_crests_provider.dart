/// The app's one [ClubCrests] (script 266), read through `TeamsApi`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'club_crests.dart';
import 'crest_shelf.dart';

/// The crests of this session: the copy kept on the device at once, the
/// list read again by the signed-in shell on every start and return to the
/// foreground. Inert under `flutter test`.
final clubCrestsProvider = Provider<ClubCrests>((ref) {
  final CrestShelf? shelf = platformCrestShelf();
  final ClubCrests crests = shelf == null
      ? ClubCrests.inert()
      : ClubCrests(
          shelf: shelf,
          readList: ref.watch(teamsApiProvider).crestManifest,
          readFile: ref.watch(teamsApiProvider).crestFile,
        );
  ref.onDispose(crests.dispose);
  unawaited(crests.start());
  return crests;
});
