import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:penguin/services/auth_session.dart';
import 'package:penguin/widgets/penguin_widgets.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController username = TextEditingController();
  final TextEditingController password = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _skipIfSignedIn();
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  // Cognito refuses a second sign-in, so an existing session goes straight home
  Future<void> _skipIfSignedIn() async {
    if (await isSignedIn() && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> checkLogin() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      showPenguinSnack(
        context,
        "All fields must be filled in",
        tone: PenguinTone.warning,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await Amplify.Auth.signIn(
        username: username.text.trim(),
        password: password.text,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (result.isSignedIn) {
          showPenguinSnack(
            context,
            'Logged in successfully!',
            tone: PenguinTone.success,
          );
          Navigator.pushReplacementNamed(context, '/home');
        } else if (result.nextStep.signInStep == AuthSignInStep.confirmSignUp) {
          showPenguinSnack(
            context,
            'Please verify your email before logging in.',
            tone: PenguinTone.warning,
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showPenguinSnack(context, e.message, tone: PenguinTone.warning);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: "Welcome back",
      subtitle: "Log in to report road damage in your city.",
      children: [
        TextFormField(
          controller: username,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: "Username or email",
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: password,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onFieldSubmitted: (_) => _isLoading ? null : checkLogin(),
          decoration: const InputDecoration(
            labelText: "Password",
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : checkLogin,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Log In"),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/signup');
          },
          child: const Text("New here? Create an account"),
        ),
      ],
    );
  }
}
