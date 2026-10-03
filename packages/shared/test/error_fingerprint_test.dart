import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _stackV1 = '''
#0      SeasonRepository.find (package:infrastructure/src/x.dart:12:5)
#1      onRequest (file:///app/routes/seasons/index.dart:40:3)
<asynchronous suspension>
#2      _rootRun (dart:async/zone.dart:1525:47)''';

// The same failure after a release moved every line.
const _stackV2 = '''
#0      SeasonRepository.find (package:infrastructure/src/x.dart:97:9)
#1      onRequest (file:///app/routes/seasons/index.dart:44:3)
<asynchronous suspension>
#2      _rootRun (dart:async/zone.dart:1530:47)''';

void main() {
  group('ErrorFingerprint', () {
    test('a known error keeps the same fingerprint and problem code', () {
      // Pinned: a player may hold this code from an older build, and the
      // web build must compute what the server computes.
      final id = ErrorFingerprint.of(
        source: 'server',
        errorType: 'StateError',
        errorCode: 'server.unexpected',
        stack: _stackV1,
        route: 'GET /seasons',
      );

      expect(id.fingerprint, 'c55fabb093f4bb0e');
      expect(id.problemCode, 'S7L9');
    });

    test('a route-only error keeps the same identity', () {
      final id = ErrorFingerprint.of(
        source: 'server',
        errorType: 'AppError',
        errorCode: 'db.timeout',
        route: 'GET /seasons/:id/fixtures',
      );

      expect(id.fingerprint, '5058b79640c21804');
      expect(id.problemCode, 'Y6PT');
    });

    test('moved lines are the same error', () {
      final a = ErrorFingerprint.of(
        source: 'server',
        errorType: 'StateError',
        stack: _stackV1,
      );
      final b = ErrorFingerprint.of(
        source: 'server',
        errorType: 'StateError',
        stack: _stackV2,
      );

      expect(a.fingerprint, b.fingerprint);
      expect(a.problemCode, b.problemCode);
    });

    test('ids and numbers in a route are the same error', () {
      final a = ErrorFingerprint.of(
        source: 'server',
        errorType: 'AppError',
        errorCode: 'db.timeout',
        route: 'GET /seasons/6bf8134c-3eed-46ce-a0dc-e3dc5d4c57c2/fixtures/12',
      );
      final b = ErrorFingerprint.of(
        source: 'server',
        errorType: 'AppError',
        errorCode: 'db.timeout',
        route: 'GET /seasons/0686dde7-bfe9-4a29-997e-a6585c334ed7/fixtures/99',
      );

      expect(a.fingerprint, b.fingerprint);
    });

    test('a different code, type or source is a different error', () {
      ErrorFingerprint of(String source, String type, String code) =>
          ErrorFingerprint.of(
            source: source,
            errorType: type,
            errorCode: code,
            stack: _stackV1,
          );
      final base = of('server', 'StateError', 'a');

      expect(
        of('server', 'StateError', 'b').fingerprint,
        isNot(base.fingerprint),
      );
      expect(
        of('server', 'RangeError', 'a').fingerprint,
        isNot(base.fingerprint),
      );
      expect(
        of('android', 'StateError', 'a').fingerprint,
        isNot(base.fingerprint),
      );
    });

    test('shapes match the table checks', () {
      final id = ErrorFingerprint.of(source: 'web', errorType: 'TypeError');

      expect(id.fingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(id.problemCode, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}$')));
    });
  });

  group('frames', () {
    test('reads VM frames, skips the SDK, keeps the line for display', () {
      final frames = ErrorFingerprint.frames(_stackV1);

      expect(frames, hasLength(2));
      expect(frames.first.file, 'package:infrastructure/src/x.dart');
      expect(frames.first.symbol, 'SeasonRepository.find');
      expect(frames.first.line, 12);
      expect(frames.last.file, 'routes/seasons/index.dart');
      expect(frames.last.line, 40);
    });

    test('reads browser frames', () {
      final frames = ErrorFingerprint.frames(
        '    at Object.a2 (https://nukhbaa.app/nukhbaa/main.dart.js:4:3)',
      );

      expect(frames.single.file, 'main.dart.js');
      expect(frames.single.symbol, 'Object.a:n');
      expect(frames.single.line, 4);
    });

    test('first-party frames come before the framework', () {
      final top = ErrorFingerprint.topFrames('''
#0      RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1:1)
#1      FixtureCard.build (package:mobile/features/fixtures/card.dart:88:7)''');

      expect(top.single.file, 'package:mobile/features/fixtures/card.dart');
    });

    test('no stack is no frame', () {
      expect(ErrorFingerprint.frames(null), isEmpty);
      expect(ErrorFingerprint.frames('   '), isEmpty);
    });
  });
}
