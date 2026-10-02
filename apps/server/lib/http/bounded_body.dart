import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The most bytes a JSON request body may carry.
///
/// Every JSON body the API accepts is small: the longest is an announcement
/// (a 120-character title and a 1,000-character body). 64 KiB leaves wide
/// room and still keeps a single request's memory negligible.
const int maxJsonBodyBytes = 64 * 1024;

/// Reads the whole body of [request], or returns `null` as soon as it grows
/// past [maxBytes].
///
/// Why: `Request.body()` and an unbounded `bytes()` fold kept every byte a
/// client chose to send. The server runs in 512 MB, so one oversized request
/// -- and the `/auth/*` routes need no account -- could take the whole API
/// down for every player. Here the read stops at the cap and the rest of the
/// upload is never buffered; the caller answers with its own `400`.
///
/// An error from the underlying stream propagates to the caller unchanged.
Future<Uint8List?> readBoundedBytes(Request request, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.bytes()) {
    if (builder.length + chunk.length > maxBytes) {
      return null;
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// The refusal of an image larger than [User.maxAvatarBytes]: the domain's
/// own avatar rule, so the client sees the same code and message whether the
/// size was caught while reading or afterwards.
AppError avatarTooLarge(String mime) =>
    switch (User.validateAvatar(User.maxAvatarBytes + 1, mime)) {
      Err<void>(:final error) => error,
      Ok<void>() => const AppError.validation(
        'identity.avatar_too_large',
        'Image is too large',
      ),
    };
