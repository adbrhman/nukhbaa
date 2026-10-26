import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/web_links.dart';

/// The link a shared card carries: the site's landing page, never an
/// invitation code (the invitations were removed on 2026-10-26).
void main() {
  test('the site at nukhbaa.app shares its landing page', () {
    expect(appSiteLink(), 'https://nukhbaa.app');
    expect(appSiteLink(), isNot(contains('ref=')));
  });

  test('a mirror that serves the web app under /nukhbaa/ shares its root', () {
    expect(
      appSiteLink(webBase: 'https://mirror.example/nukhbaa/'),
      'https://mirror.example',
    );
  });

  test('GitHub Pages has no landing page: the web app itself', () {
    expect(
      appSiteLink(webBase: 'https://adbrhman.github.io/nukhbaa/'),
      'https://adbrhman.github.io/nukhbaa/',
    );
  });
}
