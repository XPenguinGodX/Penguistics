import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:penguin/services/auth_session.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:penguin/widgets/penguin_widgets.dart';

/// The hamburger menu: who is signed in, Edit Profile, and Log out.
class PenguinMenu extends StatefulWidget {
  const PenguinMenu({super.key});

  @override
  State<PenguinMenu> createState() => _PenguinMenuState();
}

class _PenguinMenuState extends State<PenguinMenu> {
  // Created once, so reopening the drawer doesn't refetch the user
  late final Future<AuthUser> _user = Amplify.Auth.getCurrentUser();

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to send reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await signOut(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: PenguinColors.black,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  const PenguinLogo(size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FutureBuilder<AuthUser>(
                      future: _user,
                      builder: (context, snapshot) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Signed in as',
                            style: text.bodyMedium?.copyWith(
                              color: PenguinColors.muted,
                            ),
                          ),
                          Text(
                            snapshot.data?.username ?? '...',
                            style: text.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 4, color: PenguinColors.yellow),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_rounded),
              title: const Text('Edit Profile'),
              subtitle: const Text('Change your city and state'),
              onTap: () {
                // Close the drawer first so Back from the profile returns to the map
                Navigator.pop(context);
                Navigator.pushNamed(context, '/profile');
              },
            ),
            const Spacer(),
            const Divider(color: PenguinColors.outline, height: 1),
            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: PenguinColors.orange,
              ),
              title: const Text('Log out'),
              onTap: _confirmLogout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
