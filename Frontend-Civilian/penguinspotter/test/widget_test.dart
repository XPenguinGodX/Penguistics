import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:penguin/pages/login.dart';
import 'package:penguin/theme/penguin_theme.dart';

void main() {
  testWidgets('Login renders under the Midnight theme', (tester) async {
    // Amplify isn't configured in tests, so the session check counts as signed out
    await tester.pumpWidget(
      MaterialApp(theme: PenguinTheme.midnight(), home: const Login()),
    );
    await tester.pump();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('New here? Create an account'), findsOneWidget);
  });
}
