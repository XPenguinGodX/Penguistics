import 'package:flutter/material.dart';
import 'package:penguin/pages/login.dart';
import 'package:penguin/pages/home.dart';
import 'package:penguin/pages/profile.dart';
import 'package:penguin/pages/report.dart';
import 'package:penguin/pages/signup.dart';
import 'package:penguin/services/auth_session.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:penguin/amplifyconfiguration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Amplify.addPlugin(AmplifyAuthCognito());
  await Amplify.configure(amplifyconfig);
  // A returning user with a saved session skips the login screen
  final signedIn = await isSignedIn();
  runApp(Penguistics(initialRoute: signedIn ? '/home' : '/login'));
}

class Penguistics extends StatelessWidget {
  const Penguistics({super.key, required this.initialRoute});

  final String initialRoute;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: initialRoute,
      title: 'Penguistics',
      debugShowCheckedModeBanner: false,
      theme: PenguinTheme.midnight(),
      routes: {
        '/login': (context) => const Login(),
        '/signup': (context) => const Signup(),
        // Signed-in pages are wrapped so a signed-out visit bounces to /login
        '/home': (context) => const AuthGate(child: Home()),
        '/report': (context) => const AuthGate(child: Report()),
        '/profile': (context) => const AuthGate(child: ProfilePage()),
      },
    );
  }
}
