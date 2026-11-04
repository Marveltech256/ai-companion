import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../core/app_failure.dart';
import 'actions.dart';
import 'theme.dart';

String? usernameError(String? value) =>
    RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_]{2,29}$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use 3–30 letters, numbers or underscores.';
String? preferredNameError(String? value) =>
    value == null || value.trim().isEmpty
    ? 'Tell us what you would like to be called.'
    : null;

Future<void> accountDialog(
  BuildContext context,
  CompanionController controller, {
  bool reauthenticate = false,
  bool signInOnly = false,
  bool create = false,
}) => showMorrowDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AccountDialog(
    controller: controller,
    reauthenticate: reauthenticate,
    create: create || (!signInOnly && controller.anonymousAccount),
  ),
);

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.controller,
    required this.reauthenticate,
    required this.create,
  });
  final CompanionController controller;
  final bool reauthenticate, create;
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _emailForm = GlobalKey<FormState>(),
      _namesForm = GlobalKey<FormState>();
  late final TextEditingController _email, _username, _preferred;
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  late bool _create;
  bool _working = false, _finish = false;
  String? _error, _notice;
  CompanionController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _create = widget.create;
    _email = TextEditingController(text: c.accountEmail);
    _username = TextEditingController(text: c.personalProfile.username);
    _preferred = TextEditingController(text: c.personalProfile.preferredName);
  }

  @override
  void dispose() {
    for (final field in [
      _email,
      _password,
      _confirmation,
      _username,
      _preferred,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  String _message(Object e) {
    if (e is AppFailure) return e.message;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'operation-not-allowed' =>
          'This sign-in option is not available yet. Try another option.',
        'email-already-in-use' || 'credential-already-in-use' =>
          'That account already exists. Choose sign in to use it.',
        'account-exists-with-different-credential' => 'Sign in with your existing account method first. Accounts are not merged automatically.',
        'weak-password' => 'Choose a stronger password.',
        'invalid-email' => 'Enter a valid email address.',
        'network-request-failed' => 'Check your connection and try again.',
        'too-many-requests' => 'Please wait a little before trying again.',
        'popup-blocked' => 'Allow the Google sign-in popup and try again.',
        'unauthorized-domain' => 'Google sign-in is not available at this web address yet. Try email instead.',
        'user-mismatch' =>
          'Choose the Google account linked to this Ai Companion account.',
        _ => 'Could not sign in. Check your details and try again.',
      };
    }
    return 'Could not connect your account. Please try again.';
  }

  Future<void> _submit({bool google = false}) async {
    if (_working) return;
    if ((_create || _finish) && !_namesForm.currentState!.validate()) return;
    if (!_finish && !google && !_emailForm.currentState!.validate()) return;
    final previous = c.userId, wasAnonymous = c.anonymousAccount;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_finish) {
        await c.completeAccountDetails(_username.text, _preferred.text);
      } else if (google) {
        await c.authenticateGoogle(
          link:
              !widget.reauthenticate &&
              _create &&
              wasAnonymous &&
              previous != null,
          reauthenticate: widget.reauthenticate,
          username: _create ? _username.text : null,
          preferredName: _create ? _preferred.text : null,
        );
      } else if (_create) {
        await c.createAccount(
          _email.text.trim(),
          _password.text,
          username: _username.text,
          preferredName: _preferred.text,
        );
      } else {
        await c.authenticateEmail(
          _email.text.trim(),
          _password.text,
          reauthenticate: widget.reauthenticate,
        );
      }
      if (!mounted) return;
      if (!widget.reauthenticate && c.needsAccountDetails) {
        setState(() => _finish = true);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (c.registeredAccount &&
            c.needsAccountDetails &&
            (c.userId != previous || wasAnonymous || _create)) {
          _finish = true;
        }
        if (!(e is AppFailure && e.code == 'sign_in_cancelled') &&
            !(e is FirebaseAuthException &&
                {
                  'popup-closed-by-user',
                  'cancelled-popup-request',
                }.contains(e.code))) {
          _error = _message(e);
        }
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reset() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      await c.resetPassword(_email.text);
    } catch (e) {
      if (e is! FirebaseAuthException || e.code != 'user-not-found') {
        if (mounted) setState(() => _error = _message(e));
      }
    }
    if (mounted) {
      setState(() {
        _working = false;
        if (_error == null) _notice = 'If this email has an account, a password reset link has been sent.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: AlertDialog(
      title: Text(
        widget.reauthenticate
            ? 'Confirm it’s you'
            : _finish
            ? 'Make this space yours'
            : _create
            ? 'Create your account'
            : 'Welcome back',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _finish
                    ? 'You are signed in. Save your username and the name your companion should use.'
                    : _create
                    ? 'Keep your conversations with your account. Choose a username and tell us what to call you.'
                    : 'Sign in to continue with your saved companion.',
              ),
              if (_create || _finish)
                Form(
                  key: _namesForm,
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const ValueKey('account-username'),
                        controller: _username,
                        enabled: !_working,
                        maxLength: 30,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          helperText:
                              'Unique. Letters, numbers and underscores.',
                        ),
                        validator: usernameError,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('account-preferred-name'),
                        controller: _preferred,
                        enabled: !_working,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'What should I call you?',
                          hintText: 'For example, Marvin',
                        ),
                        validator: preferredNameError,
                      ),
                    ],
                  ),
                ),
              if (!_finish && c.supportsAccounts)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton(
                        onPressed: _working
                            ? null
                            : () => _submit(google: true),
                        child: Text(
                          widget.reauthenticate
                              ? 'Confirm with Google'
                              : 'Continue with Google',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Or use email', textAlign: TextAlign.center),
                    ],
                  ),
                ),
              if (!_finish)
                Form(
                  key: _emailForm,
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const ValueKey('account-email'),
                        controller: _email,
                        enabled: !_working,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) =>
                            v == null ||
                                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(v.trim())
                            ? 'Enter your email.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const ValueKey('account-password'),
                        controller: _password,
                        enabled: !_working,
                        obscureText: true,
                        autofillHints: [
                          _create
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        validator: (v) =>
                            v == null || (_create ? v.length < 8 : v.isEmpty)
                            ? (_create
                                  ? 'Use at least 8 characters.'
                                  : 'Enter your password.')
                            : null,
                      ),
                      if (_create) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const ValueKey('account-password-confirm'),
                          controller: _confirmation,
                          enabled: !_working,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                          ),
                          validator: (v) => v != _password.text
                              ? 'Passwords do not match.'
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(_notice!),
                ),
              if (!_finish && c.supportsAccounts) ...[
                if (!_create && !widget.reauthenticate)
                  TextButton(
                    onPressed: _working ? null : _reset,
                    child: const Text('Forgot password?'),
                  ),
              ],
              if (!_finish && !widget.reauthenticate)
                TextButton(
                  onPressed: _working
                      ? null
                      : () => setState(() {
                          _create = !_create;
                          _error = null;
                          _notice = null;
                          _password.clear();
                          _confirmation.clear();
                        }),
                  child: Text(
                    _create
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ActionButton(
          label: _working
              ? 'Please wait…'
              : widget.reauthenticate
              ? 'Confirm'
              : _finish
              ? 'Save my name'
              : _create
              ? 'Create account'
              : 'Sign in',
          onPressed: _working ? null : () => _submit(),
        ),
      ],
    ),
  );
}
