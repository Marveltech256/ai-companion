import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import 'theme.dart';
import 'actions.dart';

class FriendModePage extends StatelessWidget {
  const FriendModePage({
    super.key,
    required this.controller,
    required this.privacy,
  });
  final CompanionController controller;
  final VoidCallback privacy;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Brand(),
                const SizedBox(height: 30),
                const LumiOrb(size: 96),
                const SizedBox(height: 26),
                Text(
                  'A friend who gets to know you.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Personal companion mode remembers useful things you share and learns from your conversations. '
                  'This is part of the experience, so you can pick up where you left off. '
                  'Your details stay in your own account. You can correct saved information and manage your data in Privacy.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ActionButton(
                  label: 'Continue with my personal companion',
                  onPressed: controller.busy
                      ? null
                      : () => perform(
                          context,
                          controller,
                          controller.activateFriendMode,
                        ),
                ),
                TextButton(
                  onPressed: privacy,
                  child: const Text('Privacy and my data'),
                ),
                TextButton(
                  onPressed: controller.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
