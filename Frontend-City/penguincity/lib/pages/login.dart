import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:penguin_shared/penguin_shared.dart';
import 'package:penguincity/services/auth_session.dart';

/// Why [password] breaks the user pool's password policy, or null if it doesn't.
/// Mirrors PasswordPolicy in template.yaml, so staff hear about a weak password
/// before Cognito rejects it.
String? passwordProblem(String password) {
  if (password.length < 8) return 'Use at least 8 characters.';
  if (!password.contains(RegExp(r'[a-z]'))) return 'Add a lowercase letter.';
  if (!password.contains(RegExp(r'[A-Z]'))) return 'Add an uppercase letter.';
  if (!password.contains(RegExp(r'[0-9]'))) return 'Add a number.';
  if (!password.contains(RegExp(r'[^A-Za-z0-9]'))) return 'Add a symbol, like ! or #.';
  return null;
}

/// Staff login. Accounts made by an admin start with a temporary password, so the
/// first login switches this page to a "choose a new password" form.
class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isLoading = false;
  // True after Cognito answers a first login with "new password required"
  bool _needsNewPassword = false;

  @override
  void initState() {
    super.initState();
    _skipIfSignedIn();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // Cognito refuses a second sign-in, so an existing session is handled first
  Future<void> _skipIfSignedIn() async {
    final access = await staffAccess();
    if (!mounted) return;
    if (access == StaffAccess.staff) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (access == StaffAccess.notStaff) {
      await Amplify.Auth.signOut();
    }
  }

  void _warn(String message) =>
      showPenguinSnack(context, message, tone: PenguinTone.warning);

  Future<void> _logIn() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      _warn('Enter your username and password.');
      return;
    }
    await _run(
      () => Amplify.Auth.signIn(
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
  }

  Future<void> _setNewPassword() async {
    final problem = passwordProblem(_newPassword.text);
    if (problem != null) {
      _warn(problem);
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      _warn('The two passwords don\'t match.');
      return;
    }
    await _run(
      () => Amplify.Auth.confirmSignIn(confirmationValue: _newPassword.text),
    );
  }

  /// Runs one sign-in call and acts on Cognito's answer.
  Future<void> _run(Future<SignInResult> Function() call) async {
    setState(() => _isLoading = true);
    try {
      final result = await call();
      if (!mounted) return;
      await _handle(result);
    } on AuthException catch (e) {
      if (mounted) _warn(e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handle(SignInResult result) async {
    if (result.isSignedIn) {
      await _finishSignIn();
      return;
    }
    switch (result.nextStep.signInStep) {
      case AuthSignInStep.confirmSignInWithNewPassword:
        setState(() {
          _needsNewPassword = true;
          _password.clear();
        });
        showPenguinSnack(
          context,
          'Welcome! Choose your own password to finish setting up your account.',
        );
      case AuthSignInStep.resetPassword:
        _warn('Your password needs to be reset. Ask your admin for a new temporary password.');
      default:
        _warn('This account needs a sign-in step the city app doesn\'t support yet.');
    }
  }

  // Signed in, but only staff may stay: anyone else is signed straight back out
  Future<void> _finishSignIn() async {
    final access = await staffAccess();
    if (!mounted) return;
    if (access == StaffAccess.staff) {
      showPenguinSnack(context, 'Logged in successfully!', tone: PenguinTone.success);
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }
    await Amplify.Auth.signOut();
    if (!mounted) return;
    _backToLogin();
    _warn(
      'This isn\'t a city staff account. To report road damage, use the Penguistics app.',
    );
  }

  void _backToLogin() {
    setState(() {
      _needsNewPassword = false;
      _password.clear();
      _newPassword.clear();
      _confirmPassword.clear();
    });
  }

  Widget _submitButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_needsNewPassword) {
      return AuthShell(
        title: 'Choose a password',
        subtitle:
            'Your account was set up with a temporary password. Pick your own to continue.',
        children: [
          TextFormField(
            controller: _newPassword,
            obscureText: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: '8+ characters with upper and lower case, a number, and a symbol',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPassword,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _isLoading ? null : _setNewPassword(),
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 24),
          _submitButton('Set Password', _setNewPassword),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoading ? null : _backToLogin,
            child: const Text('Use a different account'),
          ),
        ],
      );
    }

    return AuthShell(
      title: 'City staff login',
      subtitle: 'Review and manage road damage reports in your city.',
      children: [
        TextFormField(
          controller: _username,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'Username or email',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _password,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onFieldSubmitted: (_) => _isLoading ? null : _logIn(),
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: 24),
        _submitButton('Log In', _logIn),
        const SizedBox(height: 12),
        Text(
          'Staff accounts are created by your admin. There is no sign-up here.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: PenguinColors.muted),
        ),
      ],
    );
  }
}
