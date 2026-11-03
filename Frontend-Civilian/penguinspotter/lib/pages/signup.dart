import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:penguin/theme/penguin_theme.dart';
import 'package:penguin/widgets/penguin_widgets.dart';

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

  Future<void> _showConfirmationDialog(
    String currentUsername,
    String cancellationToken,
  ) async {
    final codeController = TextEditingController();
    bool isBusy = false;
    bool allowClose = false;
    String? cancellationError;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: allowClose,
          child: AlertDialog(
            icon: const Icon(
              Icons.mark_email_unread_rounded,
              size: 40,
              color: PenguinColors.blue,
            ),
            title: const Text('Verify Your Email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We sent a 6-digit confirmation code to ${email.text.trim()}.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Confirmation Code',
                  ),
                ),
                if (cancellationError != null) ...[
                  const SizedBox(height: 12),
                  StatusBanner(
                    message: cancellationError!,
                    tone: PenguinTone.warning,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        setDialogState(() {
                          isBusy = true;
                          cancellationError = null;
                        });
                        try {
                          const endpoint = String.fromEnvironment(
                            'SIGNUP_CANCEL_URL',
                          );
                          final uri = Uri.tryParse(endpoint);
                          if (uri == null ||
                              uri.scheme != 'https' ||
                              uri.host.isEmpty) {
                            throw Exception(
                              'Signup cancellation is not configured yet.',
                            );
                          }
                          final result = await http
                              .post(
                                uri,
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'username': currentUsername,
                                  'token': cancellationToken,
                                }),
                              )
                              .timeout(const Duration(seconds: 20));
                          if (result.statusCode != 200 &&
                              result.statusCode != 409) {
                            throw Exception(
                              'Could not cancel signup. Please retry.',
                            );
                          }
                          if (dialogContext.mounted) {
                            setDialogState(() => allowClose = true);
                            Navigator.of(dialogContext).pop();
                          }
                          if (mounted) {
                            final alreadyConfirmed = result.statusCode == 409;
                            showPenguinSnack(
                              context,
                              alreadyConfirmed
                                  ? 'Account already confirmed. Please log in.'
                                  : 'Signup cancelled. You can try again.',
                            );
                            if (alreadyConfirmed) {
                              Navigator.pushReplacementNamed(context, '/login');
                            }
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => cancellationError = '$e');
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => isBusy = false);
                          }
                        }
                      },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        setDialogState(() => isBusy = true);
                        try {
                          await Amplify.Auth.resendSignUpCode(
                            username: currentUsername,
                          );
                          if (mounted) {
                            showPenguinSnack(
                              context,
                              'Code resent to your email!',
                            );
                          }
                        } on AuthException catch (e) {
                          if (mounted) {
                            showPenguinSnack(
                              context,
                              e.message,
                              tone: PenguinTone.warning,
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => isBusy = false);
                          }
                        }
                      },
                child: const Text('Resend Code'),
              ),
              ElevatedButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        setDialogState(() => isBusy = true);
                        try {
                          final confirmResult =
                              await Amplify.Auth.confirmSignUp(
                                username: currentUsername,
                                confirmationCode: codeController.text.trim(),
                                options: ConfirmSignUpOptions(
                                  pluginOptions:
                                      CognitoConfirmSignUpPluginOptions(
                                        clientMetadata: {
                                          'state': state.text.trim(),
                                          'city': city.text.trim(),
                                        },
                                      ),
                                ),
                              );

                          if (confirmResult.isSignUpComplete) {
                            if (dialogContext.mounted) {
                              setDialogState(() => allowClose = true);
                              Navigator.of(dialogContext).pop();
                            }
                            if (mounted) {
                              showPenguinSnack(
                                context,
                                'Account verified! Please log in.',
                                tone: PenguinTone.success,
                              );
                              Navigator.pushReplacementNamed(context, '/login');
                            }
                          }
                        } on AuthException catch (e) {
                          if (mounted) {
                            showPenguinSnack(
                              context,
                              e.message,
                              tone: PenguinTone.warning,
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => isBusy = false);
                          }
                        }
                      },
                child: const Text('Verify'),
              ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    codeController.dispose();
  }

  Future<void> onPressed() async {
    if (firstName.text.trim().isEmpty ||
        lastName.text.trim().isEmpty ||
        username.text.trim().isEmpty ||
        password.text.isEmpty ||
        email.text.trim().isEmpty ||
        state.text.trim().isEmpty ||
        city.text.trim().isEmpty) {
      showPenguinSnack(
        context,
        "All fields must be filled in",
        tone: PenguinTone.warning,
      );
      return;
    }

    if (!checkEmailFormat(email.text)) {
      showPenguinSnack(
        context,
        "Please enter a valid email address",
        tone: PenguinTone.warning,
      );
      return;
    }

    if (!checkPasswordMeetsPolicy(password.text)) {
      showPenguinSnack(
        context,
        "Password must be at least 8 characters and include uppercase, lowercase, a number, and a symbol.",
        tone: PenguinTone.warning,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final random = Random.secure();
      final cancellationToken = base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      final userAttributes = <AuthUserAttributeKey, String>{
        const CognitoUserAttributeKey.custom('signup_cancel_hash'): sha256
            .convert(utf8.encode(cancellationToken))
            .toString(),
        AuthUserAttributeKey.email: email.text.trim(),
        AuthUserAttributeKey.givenName: firstName.text.trim(),
        AuthUserAttributeKey.familyName: lastName.text.trim(),
      };

      final result = await Amplify.Auth.signUp(
        username: username.text.trim(),
        password: password.text,
        options: SignUpOptions(userAttributes: userAttributes),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (result.isSignUpComplete) {
          showPenguinSnack(
            context,
            'Sign up complete! Please log in.',
            tone: PenguinTone.success,
          );
          Navigator.pushReplacementNamed(context, '/login');
        } else {
          // Email confirmation is required by Cognito
          await _showConfirmationDialog(
            username.text.trim(),
            cancellationToken,
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: PenguinColors.muted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: "Join the colony",
      subtitle: "Create an account to start reporting road damage.",
      children: [
        _sectionLabel("Account"),
        TextFormField(
          controller: username,
          maxLength: 100,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: "Username",
            prefixIcon: Icon(Icons.person_outline_rounded),
            counterText: "",
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: "Email",
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: password,
          obscureText: true,
          maxLength: 100,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: "Password",
            prefixIcon: Icon(Icons.lock_outline_rounded),
            helperText: "8+ characters with upper, lower, number, and symbol",
            counterText: "",
          ),
        ),
        const SizedBox(height: 10),
        _sectionLabel("About you"),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: TextFormField(
                controller: firstName,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: "First name"),
              ),
            ),
            Expanded(
              child: TextFormField(
                controller: lastName,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: "Last name"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: TextFormField(
                controller: city,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: "City / Town",
                  prefixIcon: Icon(Icons.location_city_rounded),
                ),
              ),
            ),
            Expanded(
              child: TextFormField(
                controller: state,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: "State"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : onPressed,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Create Account"),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/login');
          },
          child: const Text("Already have an account? Log in"),
        ),
      ],
    );
  }
}
