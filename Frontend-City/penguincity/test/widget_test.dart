import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/pages/login.dart';
import 'package:penguincity/services/auth_session.dart';

/// A token-shaped string with these claims. The signature is fake, which is fine:
/// tokenGroups only reads claims, and the API is what verifies tokens.
String fakeToken(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part(claims)}.signature';
}

void main() {
  group('tokenGroups', () {
    test('reads the cognito:groups claim', () {
      final token = fakeToken({'cognito:groups': ['CityStaff', 'Admins']});
      expect(tokenGroups(token), {'CityStaff', 'Admins'});
    });

    test('a civilian token has no groups', () {
      expect(tokenGroups(fakeToken({'username': 'pat'})), isEmpty);
    });

    test('anything that is not a token gives no groups instead of crashing', () {
      for (final bad in ['', 'not-a-token', 'a.b', 'a.%%%.c', 'a.${base64Url.encode(utf8.encode('[1]'))}.c']) {
        expect(tokenGroups(bad), isEmpty, reason: bad);
      }
    });
  });

  group('passwordProblem', () {
    test('accepts a password that meets the pool policy', () {
      expect(passwordProblem('Penguin#2026'), isNull);
    });

    test('names the first thing missing', () {
      expect(passwordProblem('Pe#1'), contains('8 characters'));
      expect(passwordProblem('PENGUIN#2026'), contains('lowercase'));
      expect(passwordProblem('penguin#2026'), contains('uppercase'));
      expect(passwordProblem('Penguin#Ice'), contains('number'));
      expect(passwordProblem('Penguin2026'), contains('symbol'));
    });
  });

  testWidgets('Staff login renders under the Midnight theme', (tester) async {
    // Amplify isn't configured in tests, so the session check counts as signed out
    await tester.pumpWidget(
      MaterialApp(theme: PenguinTheme.midnight(), home: const Login()),
    );
    await tester.pump();

    expect(find.text('City staff login'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    // Staff can't sign themselves up
    expect(find.textContaining('Create an account'), findsNothing);
  });
}
