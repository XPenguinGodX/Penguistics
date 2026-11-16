import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';

/// The Cognito group every city staff account is in (see CityStaffGroup in template.yaml).
const staffGroup = 'CityStaff';

/// Who is using the app right now.
enum StaffAccess { signedOut, notStaff, staff }

/// The groups in a Cognito token's `cognito:groups` claim.
///
/// This only reads the token; it does not verify its signature. That is fine for
/// deciding which page to show, because the API verifies the token on every call.
/// Never use this to protect data.
Set<String> tokenGroups(String rawToken) {
  final parts = rawToken.split('.');
  if (parts.length != 3) return {};
  try {
    // The middle part is the claims: base64url-encoded JSON, usually without its = padding
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final claims = jsonDecode(json);
    final groups = claims is Map ? claims['cognito:groups'] : null;
    return groups is List ? groups.map((group) => '$group').toSet() : {};
  } catch (_) {
    return {};
  }
}

/// Checks the saved session: signed out, signed in but not staff, or staff.
Future<StaffAccess> staffAccess() async {
  try {
    final plugin = Amplify.Auth.getPlugin(AmplifyAuthCognito.pluginKey);
    final session = await plugin.fetchAuthSession();
    if (!session.isSignedIn) return StaffAccess.signedOut;
    final token = session.userPoolTokensResult.value.accessToken.raw;
    return tokenGroups(token).contains(staffGroup)
        ? StaffAccess.staff
        : StaffAccess.notStaff;
  } catch (_) {
    // Also covers Amplify not being configured yet (e.g. in widget tests)
    return StaffAccess.signedOut;
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

/// Shows [child] only to signed-in city staff; everyone else is sent to /login.
class StaffGate extends StatefulWidget {
  const StaffGate({super.key, required this.child});

  final Widget child;

  @override
  State<StaffGate> createState() => _StaffGateState();
}

class _StaffGateState extends State<StaffGate> {
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final access = await staffAccess();
    if (!mounted) return;
    if (access == StaffAccess.staff) {
      setState(() => _allowed = true);
      return;
    }
    // A civilian session must not linger here, so end it before leaving
    if (access == StaffAccess.notStaff) await Amplify.Auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return widget.child;
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
