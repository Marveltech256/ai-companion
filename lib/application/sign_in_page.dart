import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import 'account_dialog.dart';
import 'theme.dart';
import 'review_guest_dialog.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key, required this.controller, this.reconnect});
  final CompanionController controller;
  final Future<void> Function()? reconnect;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Brand(),
                const SizedBox(height: 40),
                const Center(child: LumiOrb(size: 100)),
                const SizedBox(height: 32),
                Text(
                  'A little space, just for you.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign in to meet your companion and keep your conversations with you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedInk),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: !controller.supportsAccounts || controller.busy
                      ? null
                      : () => accountDialog(
                          context,
                          controller,
                          signInOnly: true,
                        ),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: !controller.supportsAccounts || controller.busy
                      ? null
                      : () => accountDialog(context, controller, create: true),
                  child: const Text('Create account'),
                ),
                const SizedBox(height: 14),
                if (controller.reviewGuestAvailable)
                  TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => reviewGuestDialog(context, controller),
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    label: const Text('Guest for app review'),
                  ),
                const Text(
                  'For ages 18 and older. Continue with Google or your email address.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedInk, fontSize: 12),
                ),
                if (!controller.supportsAccounts && reconnect != null)
                  TextButton(
                    onPressed: reconnect,
                    child: const Text('Reconnect'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
