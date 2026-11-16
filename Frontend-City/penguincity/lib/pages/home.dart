import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/config.dart';
import 'package:penguincity/services/auth_session.dart';

/// Placeholder home page until the city map (#11) replaces it.
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      if (mounted) setState(() => _username = user.username);
    } on AuthException {
      // The name is only a greeting; the page works without it
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            PenguinLogo(size: 32),
            SizedBox(width: 10),
            PenguinWordmark(fontSize: 22),
            SizedBox(width: 8),
            Text('City'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => signOut(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _username == null ? 'Welcome' : 'Welcome, $_username',
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'The report map for your city is on its way.',
                  style: text.bodyLarge?.copyWith(color: PenguinColors.muted),
                ),
                const SizedBox(height: 24),
                // Every city API call needs PEN_API, so say so now instead of failing later
                if (penApi.isEmpty)
                  const StatusBanner(
                    message: 'PEN_API isn\'t set. Run with --dart-define=PEN_API=<ApiBaseUrl>.',
                    tone: PenguinTone.warning,
                  )
                else
                  const StatusBanner(
                    message: 'Connected to the Penguistics API.',
                    tone: PenguinTone.success,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
