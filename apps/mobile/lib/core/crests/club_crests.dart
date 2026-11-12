/// The club crests the app may show (script 266, decided by the owner on
/// 2026-11-11, before the Google Play release).
///
/// The crests are their owners' marks: none ships inside the app any more.
/// On every start, and every return to the foreground, the app reads the
/// list the owner controls (`GET /crests`, script 265) and downloads the
/// files it lacks into its [CrestShelf]. A crest that left the list -- the
/// owner hid or deleted it, or turned every club crest off -- is dropped at
/// once, file and all, and its cards draw the team's disc again. Until the
/// list is first read, the copy kept from the last start is used, so the
/// cards need no network.
///
/// The countries' flags are not marks and still ship inside the app
/// (`assets/flags`), untouched by this list.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:shared/shared.dart';

import 'crest_shelf.dart';

/// Reads the list (`TeamsApi.crestManifest`).
typedef CrestListReader = Future<Result<CrestManifestDto>> Function();

/// Reads one crest's file from its URL (`TeamsApi.crestFile`).
typedef CrestFileReader = Future<Result<Uint8List>> Function(String url);

/// The crests this device may draw, by slug. Listened to through
/// [ClubCrestScope]; never throws.
final class ClubCrests extends ChangeNotifier {
  /// Creates the crests over [shelf], read with [readList] and [readFile].
  ClubCrests({
    required CrestShelf shelf,
    required CrestListReader readList,
    required CrestFileReader readFile,
    this.parallel = 4,
  }) : _shelf = shelf,
       _readList = readList,
       _readFile = readFile;

  /// Crests that never change: none, ever (the tests, and a device with
  /// nowhere to keep them).
  ClubCrests.inert()
    : _shelf = null,
      _readList = null,
      _readFile = null,
      parallel = 1;

  final CrestShelf? _shelf;
  final CrestListReader? _readList;
  final CrestFileReader? _readFile;

  /// How many files are downloaded at once.
  final int parallel;

  /// The largest file kept (the bucket's own limit).
  static const int maxBytes = 262144;

  /// A crest's file name on the server: `<slug>.<8 hex of its sha256>.png`.
  static final RegExp _fileNamePattern = RegExp(
    r'^[a-z0-9]+(?:-[a-z0-9]+)*\.[0-9a-f]{8}\.png$',
  );

  final Map<String, ImageProvider> _images = <String, ImageProvider>{};
  final Map<String, String> _files = <String, String>{};
  bool _sharing = false;
  bool _disposed = false;
  Future<void>? _starting;
  Future<void>? _refreshing;
  String? _version;

  /// The crest of [slug], or null: the card then draws the team's disc.
  ImageProvider? imageOf(String? slug) =>
      slug == null || _sharing ? null : _images[slug];

  /// How many crests can be drawn now.
  int get count => _images.length;

  /// Draws the crests kept from the last start, before any network.
  Future<void> start() => _starting ??= _load();

  /// Reads the list again and brings the files in line with it. One read
  /// at a time; a call during one waits for it.
  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  /// Draws discs instead of crests while a card is captured to be shared:
  /// a crest never leaves the app in a picture. True when something
  /// changed, and a frame must pass before the capture.
  bool hideForSharing() {
    if (_sharing || _images.isEmpty) return false;
    _sharing = true;
    _notify();
    return true;
  }

  /// Draws the crests again after [hideForSharing].
  void showAfterSharing() {
    if (!_sharing) return;
    _sharing = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The file name in [url], or null when it is not a crest's.
  static String? fileNameOf(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.pathSegments.isEmpty) {
      return null;
    }
    final String name = uri.pathSegments.last;
    return _fileNamePattern.hasMatch(name) ? name : null;
  }

  /// Whether [bytes] is a PNG file small enough to keep.
  static bool isCrestFile(Uint8List bytes) {
    const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length || bytes.length > maxBytes) {
      return false;
    }
    for (int i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  /// The crests of [list] by slug, with their file name and URL; those
  /// whose URL names no crest file are left out.
  static Map<String, (String, String)> _wanted(
    CrestManifestDto list,
  ) => <String, (String, String)>{
    if (list.clubsEnabled)
      for (final MapEntry<String, String> e in list.crests.entries)
        if (fileNameOf(e.value) case final String name) e.key: (name, e.value),
  };

  Future<void> _load() async {
    final CrestShelf? shelf = _shelf;
    if (shelf == null) return;
    final CrestManifestDto? list = _decode(await shelf.readList());
    if (list == null || _disposed || _version != null) return;
    final Set<String> kept = shelf.keepsFiles
        ? await shelf.names()
        : const <String>{};
    if (_disposed || _version != null) return;
    for (final MapEntry<String, (String, String)> e in _wanted(list).entries) {
      final (String name, String url) = e.value;
      if (shelf.keepsFiles && !kept.contains(name)) continue;
      _files[e.key] = name;
      _images[e.key] = shelf.image(name, url);
    }
    if (_images.isNotEmpty) _notify();
  }

  Future<void> _refresh() async {
    final CrestShelf? shelf = _shelf;
    final CrestListReader? readList = _readList;
    final CrestFileReader? readFile = _readFile;
    if (shelf == null || readList == null || readFile == null) return;
    await start();
    if (_disposed) return;
    final Result<CrestManifestDto> read;
    try {
      read = await readList();
    } on Object {
      return;
    }
    // Unreadable now (offline, signed out): what is kept stays.
    if (read is! Ok<CrestManifestDto> || _disposed) return;
    final CrestManifestDto list = read.value;
    final Map<String, (String, String)> wanted = _wanted(list);

    // What left the list, or changed file, is dropped at once.
    bool changed = false;
    for (final String slug in _images.keys.toList()) {
      if (wanted[slug]?.$1 != _files[slug]) {
        _images.remove(slug);
        _files.remove(slug);
        changed = true;
      }
    }
    _version = list.version;
    if (changed) _notify();
    await shelf.writeList(jsonEncode(list.toJson()));

    if (!shelf.keepsFiles) {
      for (final MapEntry<String, (String, String)> e in wanted.entries) {
        _files[e.key] = e.value.$1;
        _images[e.key] = shelf.image(e.value.$1, e.value.$2);
      }
      _notify();
      return;
    }

    await shelf.keepOnly(<String>{
      for (final (String name, String _) in wanted.values) name,
    });
    final Set<String> kept = await shelf.names();
    final List<MapEntry<String, (String, String)>> missing =
        <MapEntry<String, (String, String)>>[];
    for (final MapEntry<String, (String, String)> e in wanted.entries) {
      final (String name, String url) = e.value;
      if (kept.contains(name)) {
        if (_files[e.key] != name) {
          _files[e.key] = name;
          _images[e.key] = shelf.image(name, url);
          changed = true;
        }
      } else {
        missing.add(e);
      }
    }
    if (changed) _notify();
    if (missing.isEmpty || _disposed) return;

    int next = 0;
    int unshown = 0;
    Future<void> worker() async {
      while (next < missing.length && !_disposed) {
        final MapEntry<String, (String, String)> e = missing[next++];
        final (String name, String url) = e.value;
        final Result<Uint8List> got;
        try {
          got = await readFile(url);
        } on Object {
          continue;
        }
        if (got is! Ok<Uint8List> || !isCrestFile(got.value)) continue;
        if (_disposed || !await shelf.put(name, got.value)) continue;
        _files[e.key] = name;
        _images[e.key] = shelf.image(name, url);
        if (++unshown >= 12) {
          unshown = 0;
          _notify();
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (int i = 0; i < parallel; i++) worker(),
    ]);
    if (unshown > 0) _notify();
  }

  static CrestManifestDto? _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is! Map<String, Object?>) return null;
      return CrestManifestDto.fromJson(decoded);
    } on Object {
      return null;
    }
  }
}

/// Hands [ClubCrests] down to every `TeamLogo`, which redraws when a crest
/// arrives or leaves.
class ClubCrestScope extends InheritedNotifier<ClubCrests> {
  /// Creates the scope over [crests].
  const ClubCrestScope({
    super.key,
    required ClubCrests crests,
    required super.child,
  }) : super(notifier: crests);

  /// The crest of [slug] for [context], which redraws when it changes; null
  /// without a scope (the tests) or without the crest.
  static ImageProvider? imageOf(BuildContext context, String? slug) {
    if (slug == null) return null;
    return context
        .dependOnInheritedWidgetOfExactType<ClubCrestScope>()
        ?.notifier
        ?.imageOf(slug);
  }

  /// The crests above [context], without listening to them.
  static ClubCrests? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ClubCrestScope>()?.notifier;
}
