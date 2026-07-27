/// Immutable runtime configuration for the Nukhba client.
///
/// The only thing the app needs to configure at boot is the base [Uri] of the
/// `apps/server` use-case API. It is supplied from a compile-time environment
/// value (`--dart-define=NUKHBA_API_BASE_URL=...`) so the same build artifact
/// can target dev / staging / prod without a code change (Deployment ADR 0007
/// — isolated environments), defaulting to a local server for development.
///
/// This holds NO secret and does NO I/O — the access token is owned by the
/// Auth layer's secure token store, never baked into config, and every network
/// call is made by `api_client`, never here.
library;

/// Runtime configuration values resolved once at application start.
final class AppConfig {
  /// Creates a configuration rooted at [apiBaseUrl].
  const AppConfig({required this.apiBaseUrl});

  /// Builds the configuration from compile-time `--dart-define` values,
  /// falling back to a local development server when unset.
  ///
  /// Example:
  /// ```
  /// flutter run --dart-define=NUKHBA_API_BASE_URL=https://api.nukhba.example
  /// ```
  factory AppConfig.fromEnvironment() {
    const raw = String.fromEnvironment(
      'NUKHBA_API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    );

    // String.fromEnvironment treats an EMPTY --dart-define as a *present*
    // value, so `defaultValue` never kicks in when CI passes an undefined
    // repository variable (`vars.NUKHBA_API_BASE_URL` -> ''). Guard explicitly:
    // an empty or relative value would silently produce Uri.parse('') and make
    // every api_client call resolve against nothing.
    if (raw.trim().isEmpty) {
      throw StateError(
        'NUKHBA_API_BASE_URL is empty. Pass it at build time, e.g. '
        '--dart-define=NUKHBA_API_BASE_URL=https://api.nukhba.example',
      );
    }

    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null || !parsed.isAbsolute || !parsed.hasAuthority) {
      throw StateError(
        'NUKHBA_API_BASE_URL must be an absolute URL with a host '
        '(got: "$raw").',
      );
    }

    return AppConfig(apiBaseUrl: parsed);
  }

  /// The base URI of the `apps/server` HTTP API (scheme + host + optional path
  /// prefix). Route-relative paths from `api_client` resolve against it.
  final Uri apiBaseUrl;

  @override
  bool operator ==(Object other) =>
      other is AppConfig && other.apiBaseUrl == apiBaseUrl;

  @override
  int get hashCode => apiBaseUrl.hashCode;

  @override
  String toString() => 'AppConfig(apiBaseUrl: $apiBaseUrl)';
}
