import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/branding/team_branding.dart';

void main() {
  group('kTeamBranding', () {
    test('is non-empty and has no duplicate-looking blank keys', () {
      expect(kTeamBranding, isNotEmpty);
      expect(kTeamBranding.keys.every((k) => k.trim().isNotEmpty), isTrue);
    });

    test('a known English club name resolves its exact legacy colors', () {
      final branding = kTeamBranding['Arsenal'];
      expect(branding, isNotNull);
      expect(branding!.primary, const Color(0xFFEF0107));
      expect(branding.secondary, const Color(0xFF063672));
    });

    test('a known Arabic team name resolves', () {
      expect(kTeamBranding['ريال مدريد'], isNotNull);
    });
  });

  group('brandingForTeam', () {
    test('returns the table entry for a known team', () {
      final branding = brandingForTeam('Liverpool');
      expect(branding.primary, kTeamBranding['Liverpool']!.primary);
    });

    test('returns a deterministic fallback for an unknown team', () {
      const name = 'A Brand New Club FC';
      final first = brandingForTeam(name);
      final second = brandingForTeam(name);
      expect(first.primary, second.primary);
      expect(first.secondary, second.secondary);
    });

    test('two different unknown teams get different fallback colors', () {
      final a = brandingForTeam('Unknown Team Alpha');
      final b = brandingForTeam('Unknown Team Beta');
      expect(a.primary, isNot(b.primary));
    });
  });

  group('teamInitials', () {
    test('single-word name -> first two letters, uppercased', () {
      expect(teamInitials('Arsenal'), 'AR');
    });

    test('multi-word name -> first letter of first two words', () {
      expect(teamInitials('Manchester United'), 'MU');
    });

    test('single-character name -> itself, uppercased', () {
      expect(teamInitials('X'), 'X');
    });

    test('blank/whitespace-only name -> "?"', () {
      expect(teamInitials('   '), '?');
    });
  });
}
