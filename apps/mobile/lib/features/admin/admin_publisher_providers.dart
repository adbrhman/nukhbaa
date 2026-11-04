/// The admin side of «النشر الرياضي الذكي» (script 209, over the routes of
/// script 208 and migration 0200). Plain providers: no code generation.
library;

import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import '../../core/ui/share_picture.dart';

/// `GET /admin/publisher`: the mode, each platform's setting, the matches
/// to pick, the latest posts, the club colours and the linked accounts.
/// Every change in the section invalidates it. A failed read shows at once
/// (`publisher.unavailable` while the server's switch is off) instead of
/// spinning through automatic retries.
final adminPublisherOverviewProvider =
    FutureProvider.autoDispose<PublisherOverviewDto>((ref) async {
      return switch (await ref.watch(adminApiProvider).publisherOverview()) {
        Ok<PublisherOverviewDto>(:final value) => value,
        Err<PublisherOverviewDto>(:final error) => throw error,
      };
    }, retry: (_, _) => null);

/// `GET /admin/publisher/posts/{id}/card`: a post's picture, read only
/// when the admin opens its preview; null when the server has none.
final adminPublisherCardProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, postId) async {
      return switch (await ref.watch(adminApiProvider).publisherCard(postId)) {
        Ok<Uint8List?>(:final value) => value,
        Err<Uint8List?>(:final error) => throw error,
      };
    }, retry: (_, _) => null);

/// The phone's share sheet, for an X post shared by hand; a test passes
/// its own.
final Provider<ShareSheet> publisherShareSheetProvider = Provider<ShareSheet>(
  (ref) => SharePlus.instance.share,
);

/// The platforms in the panel's order.
const List<String> publisherPlatforms = <String>['facebook', 'instagram', 'x'];

/// The states a post may be put back in the queue from (`retry`).
const Set<String> publisherRetryStates = <String>{
  'failed',
  'uncertain',
  'skipped',
  'cancelled',
  'dry_run',
};

/// The states a post may be cancelled from (`cancel`).
const Set<String> publisherCancelStates = <String>{'queued', 'ready_to_share'};

/// The states that wait for an admin: the log's «يحتاج تدخلك» filter.
const Set<String> publisherAttentionStates = <String>{
  'failed',
  'uncertain',
  'ready_to_share',
};

/// The bounds the server takes (`PlatformIntensity.outOfBounds`): a hold
/// of 1 to 30 minutes, a gap up to 60 minutes, a cap of 0 to 50.
const int publisherHoldMinMinutes = 1;

/// See [publisherHoldMinMinutes].
const int publisherHoldMaxMinutes = 30;

/// See [publisherHoldMinMinutes].
const int publisherGapMaxMinutes = 60;

/// See [publisherHoldMinMinutes].
const int publisherCapMax = 50;

/// What a post earned once its metrics were read: reactions, comments and
/// shares together; null before they were read.
int? publisherEngagement(PublisherPostDto post) {
  if (post.reactions == null && post.comments == null && post.shares == null) {
    return null;
  }
  return (post.reactions ?? 0) + (post.comments ?? 0) + (post.shares ?? 0);
}

/// A colour a club's disc takes: `#RRGGBB`.
bool isPublisherColour(String value) =>
    RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value);
