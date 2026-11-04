import 'package:flutter/material.dart';

import 'theme.dart';

/// The existing voice services are retained for future calling development.
/// This release does not start microphone capture or imply a call is available.
class TalkPreview extends StatelessWidget {
  const TalkPreview({super.key, required this.name, required this.chat});
  final String name;
  final VoidCallback chat;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(26),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          children: [
            const SizedBox(height: 35),
            const LumiOrb(size: 120),
            const SizedBox(height: 30),
            const Chip(label: Text('Coming soon')),
            const SizedBox(height: 20),
            Text(
              'A familiar voice, a little closer.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'We’re preparing natural, two-way voice conversations with $name. '
              'The same companion, with the context you choose to share.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Text(
              'Calling is not available yet. You can keep chatting here in the meantime.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedInk),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: chat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Back to chat'),
            ),
          ],
        ),
      ),
    ),
  );
}
