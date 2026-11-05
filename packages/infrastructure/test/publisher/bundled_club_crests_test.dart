import 'dart:io';

import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  const List<int> png = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    1,
    2,
    3,
  ];
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('nukhba_crests_');
    addTearDown(() => folder.deleteSync(recursive: true));
  });

  test('a club\'s name gives the bytes of its crest file', () async {
    File('${folder.path}/crvena-zvezda.png').writeAsBytesSync(png);
    final BundledClubCrests crests = BundledClubCrests(directory: folder.path);

    expect(await crests.crestOf('Red Star Belgrade'), png);
    // Kept: the file may go and the crest stays.
    File('${folder.path}/crvena-zvezda.png').deleteSync();
    expect(await crests.crestOf('Red Star Belgrade'), png);
  });

  test(
    'a club with no crest, no file, or a file that is no PNG is null',
    () async {
      File('${folder.path}/copenhagen.png').writeAsBytesSync(<int>[1, 2, 3]);
      final BundledClubCrests crests = BundledClubCrests(
        directory: folder.path,
      );

      expect(await crests.crestOf('Oxford City'), isNull);
      expect(await crests.crestOf('Hajduk Split'), isNull);
      expect(await crests.crestOf('FC Copenhagen'), isNull);
    },
  );

  test('fromEnv needs the folder to exist', () {
    expect(
      BundledClubCrests.fromEnv(<String, String>{
        'NUKHBA_CLUB_CRESTS': '${folder.path}/missing',
      }),
      isNull,
    );
    expect(
      BundledClubCrests.fromEnv(<String, String>{
        'NUKHBA_CLUB_CRESTS': folder.path,
      }),
      isNotNull,
    );
  });
}
