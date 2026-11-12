/// [CrestShelf] over a folder in the app's cache directory (script 266).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'crest_shelf.dart';

/// The shelf in the app's cache folder, or none under `flutter test`.
CrestShelf? platformCrestShelf() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  return FileCrestShelf(
    Directory('${Directory.systemTemp.path}/nukhba_crests'),
  );
}

/// One file per crest in [folder], named as on the server
/// (`<slug>.<hash>.png`), so a replaced crest is a new file; and the list
/// last read, `list.json`.
final class FileCrestShelf implements CrestShelf {
  /// Creates the shelf over [folder].
  FileCrestShelf(this.folder);

  /// Where the crests are kept.
  final Directory folder;

  static const String _listName = 'list.json';

  File _file(String name) => File('${folder.path}/$name');

  @override
  bool get keepsFiles => true;

  @override
  Future<String?> readList() async {
    try {
      final File list = _file(_listName);
      if (!list.existsSync()) return null;
      return await list.readAsString();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeList(String json) async {
    try {
      folder.createSync(recursive: true);
      await _file(_listName).writeAsString(json, flush: true);
    } on Object {
      // Read again from the server at the next start.
    }
  }

  @override
  Future<Set<String>> names() async {
    try {
      if (!folder.existsSync()) return <String>{};
      return <String>{
        for (final FileSystemEntity entity in folder.listSync())
          if (entity is File && entity.path.endsWith('.png'))
            entity.uri.pathSegments.last,
      };
    } on Object {
      return <String>{};
    }
  }

  @override
  Future<bool> put(String name, Uint8List bytes) async {
    try {
      folder.createSync(recursive: true);
      // Written aside, then renamed: a crest cut off half-way is never
      // drawn.
      final File part = _file('$name.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(_file(name).path);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> keepOnly(Set<String> keep) async {
    try {
      if (!folder.existsSync()) return;
      for (final FileSystemEntity entity in folder.listSync()) {
        if (entity is! File) continue;
        final String name = entity.uri.pathSegments.last;
        if (name == _listName || keep.contains(name)) continue;
        entity.deleteSync();
      }
    } on Object {
      // Removed at the next start.
    }
  }

  @override
  ImageProvider image(String name, String url) => FileImage(_file(name));
}
