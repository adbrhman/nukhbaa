/// Where the sports publisher posts (decided by the owner on 2026-11-04).
///
/// Facebook and Instagram are posted to by the server; X is prepared by the
/// server and posted by an admin by hand from the admin panel, since X has no
/// free posting tier ([PublishDelivery.manualShare]).
enum PublishPlatform {
  /// The Nukhba Facebook page.
  facebook('facebook', PublishDelivery.automatic),

  /// The Nukhba Instagram business account.
  instagram('instagram', PublishDelivery.automatic),

  /// The Nukhba X account.
  x('x', PublishDelivery.manualShare);

  const PublishPlatform(this.wire, this.delivery);

  /// The stored and wire name. A storage contract: never renamed.
  final String wire;

  /// How a post reaches the platform.
  final PublishDelivery delivery;

  /// The platform named [wire]; null for a name not known here.
  static PublishPlatform? fromWire(String wire) {
    for (final platform in PublishPlatform.values) {
      if (platform.wire == wire) {
        return platform;
      }
    }
    return null;
  }
}

/// How a prepared post reaches its platform.
enum PublishDelivery {
  /// The server calls the platform's API.
  automatic,

  /// The server prepares the picture and the text; an admin shares them.
  manualShare,
}
