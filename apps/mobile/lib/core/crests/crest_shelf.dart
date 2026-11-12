/// Where the club crests the app downloaded are kept (script 266).
///
/// The crests are their owners' marks and no longer ship inside the app:
/// the app reads the list of those it may show (`GET /crests`) on every
/// start, downloads each file once and keeps it here, so a card draws its
/// crest without the network the next time. On Android the files sit in
/// the app's cache folder (the system may clear it, which only costs a
/// download); on the web nothing is kept here and each crest is drawn from
/// its URL, which the browser caches.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'crest_shelf_stub.dart'
    if (dart.library.io) 'crest_shelf_io.dart'
    as impl;

/// The crests kept on this device. Never throws: a shelf that cannot read
/// or write only means a crest is downloaded again, or drawn as a disc.
abstract interface class CrestShelf {
  /// Whether files are kept here and drawn from here. False on the web,
  /// where a crest is drawn from its URL.
  bool get keepsFiles;

  /// The list last read from the server, as its JSON, or null.
  Future<String?> readList();

  /// Keeps [json], the list just read.
  Future<void> writeList(String json);

  /// The names of the files kept.
  Future<Set<String>> names();

  /// Keeps [bytes] as [name]; false when it could not.
  Future<bool> put(String name, Uint8List bytes);

  /// Removes every file but [keep].
  Future<void> keepOnly(Set<String> keep);

  /// The picture of file [name], downloaded from [url].
  ImageProvider image(String name, String url);
}

/// Keeps the files in memory: the tests.
final class MemoryCrestShelf implements CrestShelf {
  /// Creates an empty shelf.
  MemoryCrestShelf();

  /// The files kept, by name.
  final Map<String, Uint8List> files = <String, Uint8List>{};

  /// The list kept.
  String? list;

  @override
  bool get keepsFiles => true;

  @override
  Future<String?> readList() async => list;

  @override
  Future<void> writeList(String json) async {
    list = json;
  }

  @override
  Future<Set<String>> names() async => files.keys.toSet();

  @override
  Future<bool> put(String name, Uint8List bytes) async {
    files[name] = bytes;
    return true;
  }

  @override
  Future<void> keepOnly(Set<String> keep) async {
    files.removeWhere((String name, _) => !keep.contains(name));
  }

  @override
  ImageProvider image(String name, String url) =>
      MemoryImage(files[name] ?? Uint8List(0));
}

/// Keeps nothing: each crest is drawn from its URL (the web).
final class UrlCrestShelf implements CrestShelf {
  /// Creates the shelf.
  const UrlCrestShelf();

  @override
  bool get keepsFiles => false;

  @override
  Future<String?> readList() async => null;

  @override
  Future<void> writeList(String json) async {}

  @override
  Future<Set<String>> names() async => const <String>{};

  @override
  Future<bool> put(String name, Uint8List bytes) async => false;

  @override
  Future<void> keepOnly(Set<String> keep) async {}

  @override
  ImageProvider image(String name, String url) => NetworkImage(url);
}

/// This device's shelf, or null under `flutter test`, where no crest is
/// read unless a test gives its own.
CrestShelf? platformCrestShelf() => impl.platformCrestShelf();
