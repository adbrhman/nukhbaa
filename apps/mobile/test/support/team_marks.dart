/// The teams' marks in the tests (script 266): a club's crest is in the
/// owner's list and never in the bundle; a country's flag is in the bundle.
library;

import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/crests/club_crests.dart';
import 'package:mobile/core/crests/crest_shelf.dart';
import 'package:mobile/features/competition/team_identity.dart';
import 'package:mobile/features/competition/team_logo_assets.dart';
import 'package:shared/shared.dart';

/// A 1x1 transparent PNG: a crest file as the bucket serves it.
final Uint8List tinyPng = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 156, 99, 96, 96, 96, 96, 0, 0, 0, 5, 0, 1, 165, 246, 69, 64, 0, 0, 0, //
  0, 73, 69, 78, 68, 174, 66, 96, 130, //
]);

/// The bucket URL of [slug]'s crest file in the tests.
String crestUrlOf(String slug) =>
    'https://ref.supabase.co/storage/v1/object/public/crests/clubs/'
    '$slug.0a1b2c3d.png';

/// The slug [identity] draws: its club crest's, or its flag's.
String? markOf(ResolvedTeamIdentity identity) {
  final String? flag = identity.assetPath;
  if (flag == null) return identity.crestSlug;
  return flag.substring('assets/flags/'.length, flag.length - '.png'.length);
}

/// Expects [slug] to be drawable: a flag that loads from the bundle, or a
/// club crest of the owner's list (migration 0210).
Future<void> expectMarkAvailable(String slug) async {
  if (kFlagSlugs.contains(slug)) {
    final ByteData data = await rootBundle.load('assets/flags/$slug.png');
    expect(data.lengthInBytes, greaterThan(0), reason: slug);
  } else {
    expect(kTeamMarkSlugs, contains(slug), reason: slug);
  }
}

/// Crests holding the files of [slugs], as a phone holds them once the list
/// was read: for a `ClubCrestScope` in a widget test.
Future<ClubCrests> crestsHolding(Iterable<String> slugs) async {
  final ClubCrests crests = ClubCrests(
    shelf: MemoryCrestShelf(),
    readList: () async => Result.ok(
      CrestManifestDto(
        version: 'v1',
        clubsEnabled: true,
        crests: <String, String>{
          for (final String slug in slugs) slug: crestUrlOf(slug),
        },
      ),
    ),
    readFile: (String url) async => Result.ok(tinyPng),
  );
  await crests.refresh();
  return crests;
}
