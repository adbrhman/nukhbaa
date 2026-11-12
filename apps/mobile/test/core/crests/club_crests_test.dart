/// The club crests a phone may draw (script 266): read from the owner's
/// list, kept on the phone, dropped the moment they leave the list, and
/// never in a shared picture.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/crests/club_crests.dart';
import 'package:mobile/core/crests/crest_shelf.dart';
import 'package:shared/shared.dart';

import '../../support/team_marks.dart';

final class _Server {
  Map<String, String> crests = <String, String>{
    'arsenal': crestUrlOf('arsenal'),
    'chelsea': crestUrlOf('chelsea'),
  };
  bool enabled = true;
  bool reachable = true;
  final List<String> downloads = <String>[];
  Uint8List file = tinyPng;

  Future<Result<CrestManifestDto>> list() async => reachable
      ? Result.ok(
          CrestManifestDto(
            version: 'v${crests.length}',
            clubsEnabled: enabled,
            crests: enabled ? crests : const <String, String>{},
          ),
        )
      : const Result.err(AppError.transient('net', 'offline'));

  Future<Result<Uint8List>> read(String url) async {
    downloads.add(url);
    return Result.ok(file);
  }
}

ClubCrests _crests(_Server server, CrestShelf shelf) =>
    ClubCrests(shelf: shelf, readList: server.list, readFile: server.read);

void main() {
  test('reads the list, downloads each file once, draws each crest', () async {
    final _Server server = _Server();
    final MemoryCrestShelf shelf = MemoryCrestShelf();
    final ClubCrests crests = _crests(server, shelf);
    addTearDown(crests.dispose);

    await crests.refresh();
    await crests.refresh();

    expect(crests.imageOf('arsenal'), isA<MemoryImage>());
    expect(crests.imageOf('chelsea'), isNotNull);
    expect(crests.imageOf('milan'), isNull);
    expect(server.downloads, hasLength(2));
    expect(shelf.files.keys.toSet(), <String>{
      'arsenal.0a1b2c3d.png',
      'chelsea.0a1b2c3d.png',
    });
  });

  test('a crest the owner hides is dropped at once, file and all', () async {
    final _Server server = _Server();
    final MemoryCrestShelf shelf = MemoryCrestShelf();
    final ClubCrests crests = _crests(server, shelf);
    addTearDown(crests.dispose);
    await crests.refresh();
    int changes = 0;
    crests.addListener(() => changes++);

    server.crests = <String, String>{'chelsea': crestUrlOf('chelsea')};
    await crests.refresh();

    expect(crests.imageOf('arsenal'), isNull);
    expect(crests.imageOf('chelsea'), isNotNull);
    expect(shelf.files.keys.toSet(), <String>{'chelsea.0a1b2c3d.png'});
    expect(changes, greaterThan(0));
  });

  test('with club crests off, every crest goes', () async {
    final _Server server = _Server();
    final MemoryCrestShelf shelf = MemoryCrestShelf();
    final ClubCrests crests = _crests(server, shelf);
    addTearDown(crests.dispose);
    await crests.refresh();

    server.enabled = false;
    await crests.refresh();

    expect(crests.count, 0);
    expect(shelf.files, isEmpty);
  });

  test('offline, the crests kept from the last start are drawn', () async {
    final _Server server = _Server();
    final MemoryCrestShelf shelf = MemoryCrestShelf();
    final ClubCrests first = _crests(server, shelf);
    await first.refresh();
    first.dispose();

    server.reachable = false;
    final ClubCrests next = _crests(server, shelf);
    addTearDown(next.dispose);
    await next.start();
    await next.refresh();

    expect(next.imageOf('arsenal'), isNotNull);
    expect(server.downloads, hasLength(2));
  });

  test('a file kept without its list entry is not drawn', () async {
    final MemoryCrestShelf shelf = MemoryCrestShelf()
      ..files['milan.0a1b2c3d.png'] = tinyPng
      ..list = jsonEncode(
        const CrestManifestDto(
          version: 'v0',
          clubsEnabled: true,
          crests: <String, String>{},
        ).toJson(),
      );
    final ClubCrests crests = _crests(_Server(), shelf);
    addTearDown(crests.dispose);

    await crests.start();

    expect(crests.imageOf('milan'), isNull);
  });

  test(
    'a file that is not a PNG, or a URL that is not a crest, is not kept',
    () async {
      final _Server server = _Server()
        ..file = Uint8List.fromList(utf8.encode('<html>'))
        ..crests = <String, String>{
          'arsenal': crestUrlOf('arsenal'),
          'evil': 'http://elsewhere.example/clubs/evil.0a1b2c3d.png',
        };
      final MemoryCrestShelf shelf = MemoryCrestShelf();
      final ClubCrests crests = _crests(server, shelf);
      addTearDown(crests.dispose);

      await crests.refresh();

      expect(crests.count, 0);
      expect(shelf.files, isEmpty);
      expect(server.downloads, <String>[crestUrlOf('arsenal')]);
    },
  );

  test('a shared picture draws the discs, then the crests come back', () async {
    final ClubCrests crests = await crestsHolding(<String>['arsenal']);
    addTearDown(crests.dispose);

    expect(crests.hideForSharing(), isTrue);
    expect(crests.imageOf('arsenal'), isNull);
    crests.showAfterSharing();
    expect(crests.imageOf('arsenal'), isNotNull);
  });

  test('with no crest drawn, sharing changes nothing', () {
    final ClubCrests crests = ClubCrests.inert();
    addTearDown(crests.dispose);

    expect(crests.hideForSharing(), isFalse);
  });

  test('the web keeps no file and draws each crest from its URL', () async {
    final _Server server = _Server();
    final ClubCrests crests = _crests(server, const UrlCrestShelf());
    addTearDown(crests.dispose);

    await crests.refresh();

    expect(crests.imageOf('arsenal'), isA<NetworkImage>());
    expect(server.downloads, isEmpty);
  });

  test('a crest file name is the one on the server', () {
    expect(
      ClubCrests.fileNameOf(crestUrlOf('aston-villa')),
      'aston-villa.0a1b2c3d.png',
    );
    expect(ClubCrests.fileNameOf('https://x/clubs/../../etc.png'), isNull);
    expect(
      ClubCrests.fileNameOf('https://x/clubs/Arsenal.0a1b2c3d.png'),
      isNull,
    );
  });
}
