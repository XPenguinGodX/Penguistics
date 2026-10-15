import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';

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
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> checkLogin() async {
      try {
        final currentSession = await Amplify.Auth.fetchAuthSession();
        if (currentSession.isSignedIn) {
          await Amplify.Auth.signOut();
        }
      } catch (_) {}

    if (username.text.trim().isEmpty || password.text.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: Colors.white,
            content: Text(
              "All fields must be filled in",
              style: TextStyle(color: Colors.black, fontSize: 16),
            ),
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('Logged in successfully!'),
            ),
          );
          Navigator.pushReplacementNamed(context, '/home');
        } else if (result.nextStep.signInStep == AuthSignInStep.confirmSignUp) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orangeAccent,
              content: Text('Please verify your email before logging in.'),
            ),
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(e.message, style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          color: Colors.amber,
          width: 500.0,
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Login",
                style: TextStyle(fontSize: 50, color: Colors.white),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: username,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: "Enter your username or email",
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: "Enter your password",
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _isLoading ? null : checkLogin,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(Colors.white),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        "Submit",
                        style: TextStyle(color: Colors.black, fontSize: 16),
                      ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/signup');
                },
                child: const Text(
                  "Create An Account",
                  style: TextStyle(color: Colors.white),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
