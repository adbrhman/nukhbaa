/// The app's install id (script 200): a random id the Android app keeps in
/// its secure store (`nukhba.install_id`, since migration 0073) and sends in
/// the `x-nukhba-install` header. One install is one phone; clearing the
/// app's data makes a new one.
abstract final class InstallId {
  static final RegExp _shape = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// [raw] as an install id (trimmed, lower case), or null when it is
  /// missing or not one: such a request is simply not tied to a phone.
  static String? parse(String? raw) {
    if (raw == null) {
      return null;
    }
    final String id = raw.trim().toLowerCase();
    return _shape.hasMatch(id) ? id : null;
  }
}
