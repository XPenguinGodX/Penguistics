import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';

/// True when Cognito holds a valid session; any lookup failure counts as signed out.
Future<bool> isSignedIn() async {
  try {
    final session = await Amplify.Auth.fetchAuthSession();
    return session.isSignedIn;
  } catch (_) {
    // Also covers Amplify not being configured yet (e.g. in widget tests)
    return false;
  }
}

/// The raw Cognito access token, sent to the API as a Bearer header.
Future<String> accessToken() async {
  final plugin = Amplify.Auth.getPlugin(AmplifyAuthCognito.pluginKey);
  final session = await plugin.fetchAuthSession();
  if (!session.isSignedIn) {
    throw Exception('Please log in again.');
  }
  return session.userPoolTokensResult.value.accessToken.raw;
}

/// Ends the session and clears the page history so Back can't reopen the app.
Future<void> signOut(BuildContext context) async {
  await Amplify.Auth.signOut();
  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }
}

/// Shows [child] only to signed-in users; everyone else is sent to /login.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final signedIn = await isSignedIn();
    if (!mounted) return;
    if (signedIn) {
      setState(() => _allowed = true);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return widget.child;
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
