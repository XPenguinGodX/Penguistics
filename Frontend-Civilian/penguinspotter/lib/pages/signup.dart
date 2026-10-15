import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

bool checkPasswordMeetsPolicy(String password) {
  if (password.length < 8) return false;
  if (!RegExp(r'[a-z]').hasMatch(password)) return false;
  if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
  if (!RegExp(r'[0-9]').hasMatch(password)) return false;
  // Matches any symbol / non-alphanumeric character
  if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) return false;
  return true;
}

bool checkEmailFormat(String email) {
  final emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  return emailRegex.hasMatch(email.trim());
}


class _SignupState extends State<Signup> {
  final TextEditingController firstName = TextEditingController();
  final TextEditingController lastName = TextEditingController();
  final TextEditingController username = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController state = TextEditingController();
  final TextEditingController city = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    username.dispose();
    password.dispose();
    email.dispose();
    state.dispose();
    city.dispose();
    super.dispose();
  }

  void _showConfirmationDialog(String currentUsername) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verify Your Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('We sent a 6-digit confirmation code to ${email.text.trim()}.'),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Confirmation Code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await Amplify.Auth.resendSignUpCode(username: currentUsername);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code resent to your email!')),
                  );
                }
              } on AuthException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text(e.message),
                    ),
                  );
                }
              }
            },
            child: const Text('Resend Code'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final confirmResult = await Amplify.Auth.confirmSignUp(
                  username: currentUsername,
                  confirmationCode: codeController.text.trim(),
                );

                if (confirmResult.isSignUpComplete) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.green,
                        content: Text('Account verified! Please log in.'),
                      ),
                    );
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                }
              } on AuthException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text(e.message),
                    ),
                  );
                }
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> onPressed() async {
    if (firstName.text.trim().isEmpty ||
        lastName.text.trim().isEmpty ||
        username.text.trim().isEmpty ||
        password.text.isEmpty ||
        email.text.trim().isEmpty ||
        state.text.trim().isEmpty ||
        city.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: Colors.white70,
            content: Text(
              "All fields must be filled in",
              style: TextStyle(color: Colors.black, fontSize: 16),
            ),
          ),
        );
      return;
    }

    if (!checkEmailFormat(email.text)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              "Please enter a valid email address",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        );
      return;
    }

    if (!checkPasswordMeetsPolicy(password.text)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              "Password must be at least 8 characters and include uppercase, lowercase, a number, and a symbol.",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userAttributes = <AuthUserAttributeKey, String>{
        AuthUserAttributeKey.email: email.text.trim(),
        AuthUserAttributeKey.givenName: firstName.text.trim(),
        AuthUserAttributeKey.familyName: lastName.text.trim(),
      };

      final result = await Amplify.Auth.signUp(
        username: username.text.trim(),
        password: password.text,
        options: SignUpOptions(
          userAttributes: userAttributes,
        ),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (result.isSignUpComplete) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('Sign up complete! Please log in.'),
            ),
          );
          Navigator.pushReplacementNamed(context, '/login');
        } else {
          // Email confirmation is required by Cognito
          _showConfirmationDialog(username.text.trim());
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
      backgroundColor: Colors.blueAccent,
      body: Center(
        child: SizedBox(
          width: 400,
          child: Column(
            spacing: 5,
            children: [
              Text("Sign Up"),
              Text("Username"),
              TextFormField(
                controller: username,
                maxLength: 100,
                decoration: InputDecoration(hint: Text("Enter a Username")),
              ),
              Text("Password"),
              TextFormField(
                controller: password,
                obscureText: true,
                maxLength: 100,
                decoration: InputDecoration(hint: Text("Enter a Password")),
              ),
              Text("Email"),
              TextFormField(
                controller: email,
                decoration: InputDecoration(hint: Text("Enter an Email")),
              ),
              Text("First Name"),
              TextFormField(
                controller: firstName,
                decoration: InputDecoration(
                  hint: Text("Enter your First Name"),
                ),
              ),
              Text("Last Name"),
              TextFormField(
                controller: lastName,
                decoration: InputDecoration(hint: Text("Enter your Last Name")),
              ),
              Text("State"),
              TextFormField(
                controller: state,
                decoration: InputDecoration(
                  hint: Text("What State are you in?"),
                ),
              ),
              Text("City/Town"),
              TextFormField(
                controller: city,
                decoration: InputDecoration(hint: Text("Enter your City/Town")),
              ),
              TextButton(
                onPressed: _isLoading ? null : onPressed,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Create"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text(
                  "Already have an account? Log in",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
