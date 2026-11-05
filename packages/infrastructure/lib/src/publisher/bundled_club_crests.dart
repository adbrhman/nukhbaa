import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';

/// [ClubCrestSource] over the crest PNGs the server image carries
/// (`/app/team_logos`, the app's own `assets/team_logos/` folder): a club's
/// name gives its slug ([ClubCrests]), the slug its file.
///
/// A file is kept in memory once read (about 5 KB each). A club with no
/// crest, a missing file or a file that is not a PNG gives null, and the
/// picture draws that club as the disc of its colour.
final class BundledClubCrests implements ClubCrestSource {
  /// Reads crests from [directory].
  BundledClubCrests({required this.directory});

  /// The folder the server image carries, or `NUKHBA_CLUB_CRESTS`; null
  /// when it is missing, so a server without it draws every club as a disc.
  static BundledClubCrests? fromEnv(Map<String, String> env) {
    final folder = (env['NUKHBA_CLUB_CRESTS'] ?? '/app/team_logos').trim();
    if (!Directory(folder).existsSync()) {
      return null;
    }
    return BundledClubCrests(directory: folder);
  }

  /// The folder of `<slug>.png` files.
  final String directory;

  final Map<String, List<int>> _kept = <String, List<int>>{};

  static const List<int> _pngSignature = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  @override
  Future<List<int>?> crestOf(String clubName) async {
    final slug = ClubCrests.slugFor(clubName);
    if (slug == null) {
      return null;
    }
    final kept = _kept[slug];
    if (kept != null) {
      return kept;
    }
    try {
      final file = File('$directory/$slug.png');
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (!_isPng(bytes)) {
        return null;
      }
      _kept[slug] = bytes;
      return bytes;
    } on Object {
      return null;
    }
  }

  static bool _isPng(List<int> bytes) {
    if (bytes.length < _pngSignature.length) {
      return false;
    }
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) {
        return false;
      }
    }
    return true;
  }
}
