import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/amplifyconfiguration.dart';
import 'package:penguincity/pages/home.dart';
import 'package:penguincity/pages/login.dart';
import 'package:penguincity/services/auth_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Amplify.addPlugin(AmplifyAuthCognito());
  await Amplify.configure(amplifyconfig);
  // Returning staff with a saved session skip the login screen; StaffGate re-checks the group
  final access = await staffAccess();
  runApp(PenguinCity(initialRoute: access == StaffAccess.staff ? '/home' : '/login'));
}

class PenguinCity extends StatelessWidget {
  const PenguinCity({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: initialRoute,
      title: 'Penguistics City',
      debugShowCheckedModeBanner: false,
      theme: PenguinTheme.midnight(),
      routes: {
        '/login': (context) => const Login(),
        // Staff-only pages are wrapped so anyone else bounces to /login
        '/home': (context) => const StaffGate(child: Home()),
      },
    );
  }
}
