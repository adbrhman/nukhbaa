/// Pictures in the support chat (migration 0188, script 168): picking one,
/// checking it before it is sent, and drawing a stored one, read through
/// the signed-in transport.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/providers.dart';
import '../../core/ui/app_skeleton.dart';
import 'support_providers.dart';

/// A picture picked on the device, ready to send.
final class SupportPickedImage {
  const SupportPickedImage({required this.bytes, required this.mime});

  final Uint8List bytes;
  final String mime;
}

/// The server's limit (0188): 512 KB.
const int supportImageMaxBytes = 512 * 1024;

/// The type a picture's own bytes say it is: JPEG, PNG or WEBP, else null.
String? supportImageMime(List<int> bytes) {
  bool starts(List<int> prefix, [int at = 0]) {
    if (bytes.length < at + prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (bytes[at + i] != prefix[i]) return false;
    }
    return true;
  }

  if (starts(const <int>[0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts(const <int>[0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts(const <int>[0x52, 0x49, 0x46, 0x46]) &&
      starts(const <int>[0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return null;
}

/// Opens the gallery; null when nothing was picked. The picker shrinks a
/// photo to 1280 px at 75% quality, well under 512 KB for a screenshot, so
/// it is not refused after it was sent. Replaced in tests.
final Provider<Future<SupportPickedImage?> Function()>
supportImagePickerProvider = Provider<Future<SupportPickedImage?> Function()>(
  (ref) => () async {
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (picked == null) return null;
    final Uint8List bytes = await picked.readAsBytes();
    return SupportPickedImage(
      bytes: bytes,
      mime: supportImageMime(bytes) ?? '',
    );
  },
);

/// Picks a picture and shows it before it is sent: the picture, then
/// «إرسال» or «إلغاء». Null when the player changed his mind; a line says
/// why a picture cannot be sent (not a picture, or too large).
Future<SupportPickedImage?> pickSupportImage(
  BuildContext context,
  WidgetRef ref,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final SupportPickedImage? picked;
  try {
    picked = await ref.read(supportImagePickerProvider)();
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text('تعذّر فتح الصور. حاول مرة أخرى.')),
    );
    return null;
  }
  if (picked == null || !context.mounted) return null;
  final String? problem = picked.mime.isEmpty
      ? 'أرسل صورة بصيغة JPEG أو PNG أو WEBP.'
      : (picked.bytes.length > supportImageMaxBytes
            ? 'الصورة أكبر من 512 كيلوبايت. اختر صورة أصغر.'
            : null);
  if (problem != null) {
    messenger.showSnackBar(
      SnackBar(key: const Key('support.image.refused'), content: Text(problem)),
    );
    return null;
  }
  final bool? send = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      key: const Key('support.image.preview'),
      title: const Text('إرسال هذه الصورة؟'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ClipRRect(
          borderRadius: AppRadius.brMd,
          child: Image.memory(picked!.bytes, fit: BoxFit.contain),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('support.image.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('support.image.send'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('إرسال'),
        ),
      ],
    ),
  );
  return send == true ? picked : null;
}

/// Which stored picture: the player's own chat (conversation null) or one
/// conversation an admin reads, and the message.
typedef SupportImageRef = ({String? conversationId, int messageId});

/// A stored picture's bytes, read once through the signed-in transport
/// (`Image.network` cannot carry the token on the web). Null when there is
/// none to read.
final supportImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, SupportImageRef>((ref, SupportImageRef key) async {
      final String? conversation = key.conversationId;
      final Result<Uint8List?> result = conversation == null
          ? await ref.watch(supportApiProvider).image(key.messageId)
          : await ref
                .watch(adminApiProvider)
                .supportImage(conversation, key.messageId);
      return switch (result) {
        Ok<Uint8List?>(:final value) => value,
        Err<Uint8List?>(:final error) => throw error,
      };
    });

/// A picture inside a bubble: a stored one ([imageRef]) or one still being
/// sent ([localBytes]). A tap opens it full screen.
class SupportImageThumb extends ConsumerWidget {
  const SupportImageThumb({super.key, this.imageRef, this.localBytes})
    : assert(imageRef != null || localBytes != null, 'a picture to draw');

  final SupportImageRef? imageRef;
  final Uint8List? localBytes;

  static const double _width = 220;
  static const double _height = 160;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final Uint8List? local = localBytes;
    final AsyncValue<Uint8List?>? stored = imageRef == null
        ? null
        : ref.watch(supportImageBytesProvider(imageRef!));
    final Uint8List? bytes = local ?? stored?.value;
    final Widget child;
    if (bytes != null) {
      child = GestureDetector(
        key: const Key('support.image.open'),
        onTap: () => unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => _SupportImageViewer(bytes: bytes),
            ),
          ),
        ),
        child: Image.memory(
          bytes,
          key: const Key('support.image'),
          width: _width,
          height: _height,
          fit: BoxFit.cover,
        ),
      );
    } else if (stored != null && stored.hasError) {
      child = SizedBox(
        key: const Key('support.image.failed'),
        width: _width,
        height: _height,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: AppSizes.iconStateLg,
            color: tokens.textMuted,
          ),
        ),
      );
    } else {
      child = const AppSkeleton(
        key: Key('support.image.loading'),
        width: _width,
        height: _height,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ClipRRect(borderRadius: AppRadius.brMd, child: child),
    );
  }
}

class _SupportImageViewer extends StatelessWidget {
  const _SupportImageViewer({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('support.image.viewer'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
