/// What makes two error reports the same error (migration 0087).
library;

import 'dart:convert';

/// One frame of a stack trace, as far as the error log cares: the member
/// that was running and the file it lives in, plus the line for display.
final class ErrorFrame {
  /// Creates a frame.
  const ErrorFrame({required this.symbol, required this.file, this.line});

  /// The member, ids and numbers replaced (`SeasonRepository.find`).
  final String symbol;

  /// The file, shortened to its package or `lib/` / `routes/` path.
  final String file;

  /// The line, for display only: it never enters the fingerprint, so a
  /// line that moved in a later build is still the same error.
  final int? line;
}

/// The identity of an error in the error log: a 16-hex-digit
/// [fingerprint] and the 4-character [problemCode] a player reads out.
///
/// Both come from the source, the error's type and code, and the top
/// frames of its stack -- members and files, never line numbers, never
/// variable ids or numbers -- or the route when the stack has no usable
/// frame. The same function runs on the server and in the app, so the app
/// can show the problem code while offline and the server stores the same
/// one.
final class ErrorFingerprint {
  const ErrorFingerprint._(this.fingerprint, this.problemCode);

  /// Computes the identity of an error.
  factory ErrorFingerprint.of({
    required String source,
    required String errorType,
    String? errorCode,
    String? stack,
    String? route,
  }) {
    final frames = topFrames(stack);
    final where = frames.isNotEmpty
        ? frames.map((f) => '${f.file} ${f.symbol}').join('|')
        : normalizeVariable(route ?? '');
    final basis = [
      source,
      normalizeVariable(errorType),
      errorCode ?? '',
      where,
    ].join('\n');
    final bytes = utf8.encode(basis);
    final high = _fnv1a32(bytes, 0x811c9dc5);
    final low = _fnv1a32(bytes, 0x050c5d1f);
    final hex =
        high.toRadixString(16).padLeft(8, '0') +
        low.toRadixString(16).padLeft(8, '0');
    final code = StringBuffer();
    var bits = high;
    for (var i = 0; i < 4; i++) {
      code.write(problemCodeAlphabet[bits % 32]);
      bits = bits ~/ 32;
    }
    return ErrorFingerprint._(hex, code.toString());
  }

  /// 16 lowercase hex digits.
  final String fingerprint;

  /// 4 characters of [problemCodeAlphabet].
  final String problemCode;

  /// No `0`/`O` and no `1`/`I`, so a code read aloud is not misheard.
  static const String problemCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// How many frames identify an error.
  static const int frameCount = 3;

  /// The first-party packages: their frames are preferred over the
  /// framework's, which every error shares.
  static const List<String> firstParty = [
    'package:mobile/',
    'package:server/',
    'package:application/',
    'package:domain/',
    'package:infrastructure/',
    'package:api_client/',
    'package:contracts/',
    'package:shared/',
    'routes/',
    'lib/',
  ];

  static final RegExp _vmFrame = RegExp(r'^#\d+\s+(.+?)\s+\((.+)\)\s*$');
  static final RegExp _jsFrame = RegExp(r'^\s*at\s+(.+?)\s+\((.+)\)\s*$');
  static final RegExp _position = RegExp(r':(\d+)(?::\d+)?$');
  static final RegExp _uuid = RegExp(
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    '[0-9a-fA-F]{12}',
  );
  static final RegExp _longHex = RegExp(
    r'\b(?=[0-9a-fA-F]*\d)[0-9a-fA-F]{8,}\b',
  );
  static final RegExp _digits = RegExp(r'\d+');

  /// Replaces the parts of [text] that differ between two occurrences of
  /// the same error: uuids and long hex become `:id`, numbers `:n`.
  static String normalizeVariable(String text) => text
      .replaceAll(_uuid, ':id')
      .replaceAll(_longHex, ':id')
      .replaceAll(_digits, ':n');

  /// Every frame of [stack] in order, skipping the SDK and async gaps.
  static List<ErrorFrame> frames(String? stack) {
    if (stack == null || stack.trim().isEmpty) {
      return const [];
    }
    final out = <ErrorFrame>[];
    for (final raw in const LineSplitter().convert(stack)) {
      final match = _vmFrame.firstMatch(raw) ?? _jsFrame.firstMatch(raw);
      if (match == null) {
        continue;
      }
      final location = match.group(2)!.trim();
      if (location.startsWith('dart:') || location == '<anonymous>') {
        continue;
      }
      final position = _position.firstMatch(location);
      final file = _shortFile(
        position == null ? location : location.substring(0, position.start),
      );
      out.add(
        ErrorFrame(
          symbol: normalizeVariable(match.group(1)!.trim()),
          file: file,
          line: position == null ? null : int.tryParse(position.group(1)!),
        ),
      );
    }
    return out;
  }

  /// The frames that identify the error: the top [frameCount] first-party
  /// frames, or the top [frameCount] of any kind when none is first-party.
  static List<ErrorFrame> topFrames(String? stack) {
    final all = frames(stack);
    final own = all.where((f) => _isFirstParty(f.file)).toList();
    return (own.isNotEmpty ? own : all).take(frameCount).toList();
  }

  static bool _isFirstParty(String file) =>
      firstParty.any((prefix) => file.startsWith(prefix));

  // `package:x/y.dart` stays; a file path keeps only its `routes/...` or
  // `lib/...` tail; a URL keeps only its last segment.
  static String _shortFile(String location) {
    if (location.startsWith('package:')) {
      return location;
    }
    for (final marker in const ['/routes/', '/lib/']) {
      final at = location.lastIndexOf(marker);
      if (at >= 0) {
        return location.substring(at + 1);
      }
    }
    final slash = location.lastIndexOf('/');
    return slash >= 0 ? location.substring(slash + 1) : location;
  }

  // FNV-1a over 32 bits. Every intermediate stays below 2^53, so the web
  // build (JavaScript numbers) computes the same value as the server.
  static int _fnv1a32(List<int> bytes, int basis) {
    var hash = basis;
    for (final byte in bytes) {
      hash = _xor8(hash, byte);
      hash = _mul32(hash, 0x01000193);
    }
    return hash;
  }

  // XOR of the low 8 bits of [hash] with [byte], without bitwise operators
  // on values above 2^31 (JavaScript bitwise operators are signed 32-bit).
  static int _xor8(int hash, int byte) {
    final lowByte = hash % 256;
    var mixed = 0;
    var bit = 1;
    for (var i = 0; i < 8; i++) {
      final a = (lowByte ~/ bit) % 2;
      final b = (byte ~/ bit) % 2;
      if (a != b) {
        mixed += bit;
      }
      bit *= 2;
    }
    return hash - lowByte + mixed;
  }

  // (a * b) mod 2^32 for a < 2^32 and b < 2^25, split so no product
  // passes 2^53.
  static int _mul32(int a, int b) {
    final aLow = a % 65536;
    final aHigh = a ~/ 65536;
    final low = aLow * b;
    final high = ((aHigh * b) % 65536) * 65536;
    return (low + high) % 4294967296;
  }
}
