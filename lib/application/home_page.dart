import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import 'personalization.dart';
import 'reminders.dart';
import 'theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.deviceOnly,
    required this.talk,
    required this.voice,
    required this.memories,
    required this.settings,
  });
  final CompanionController controller;
  final bool deviceOnly;
  final VoidCallback talk, voice, memories, settings;

  @override
  Widget build(BuildContext context) {
    final c = controller, summary = c.homeSummary;
    final clock = summary?['clock'] as Map?;
    final local = DateTime.tryParse(clock?['local'] as String? ?? '');
    final last = DateTime.tryParse(
      summary?['last_user_message_at'] as String? ?? '',
    );
    final reminders = (summary?['reminders'] as List? ?? []).cast<Map>();
    final events = (summary?['events'] as List? ?? []).cast<Map>();
    final name =
        c.personalProfile.preferredName ??
        c.displayName?.split(' ').firstOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                homeGreeting(
                  name,
                  c.personalProfile.language,
                  local,
                  last,
                  DateTime.now(),
                ),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                last == null
                    ? 'A little space to get to know each other.'
                    : 'We can pick up wherever you like.',
                style: const TextStyle(color: mutedInk),
              ),
              const SizedBox(height: 26),
              Panel(
                color: lilac,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 30,
                ),
                child: Column(
                  children: [
                    const LumiOrb(size: 112),
                    const SizedBox(height: 24),
                    Text(
                      c.companion!.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      deviceOnly
                          ? 'A little space for you.'
                          : 'Want to talk for a while?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      deviceOnly
                          ? 'Keep your thoughts and the things that matter.'
                          : 'Your AI companion is here. Start with whatever is on your mind.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: mutedInk),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: talk,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(
                        deviceOnly
                            ? 'Write a little moment'
                            : c.conversations.isEmpty
                            ? 'Start chatting'
                            : 'Continue chatting',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: voice,
                      icon: const Icon(Icons.graphic_eq, size: 18),
                      label: const Text('Talk · Coming soon'),
                    ),
                  ],
                ),
              ),
              if (c.conversations.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text(
                  'Our recent conversations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Panel(
                  child: Column(
                    children: [
                      for (final conversation in c.conversations.take(3))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.chat_bubble_outline,
                            color: plum,
                          ),
                          title: Text(
                            conversation.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: c.sending
                              ? null
                              : () async {
                                  await c.openConversation(conversation);
                                  talk();
                                },
                        ),
                    ],
                  ),
                ),
              ],
              if (reminders.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text(
                  'Coming up',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Panel(
                  child: Column(
                    children: [
                      for (final reminder in reminders)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.notifications_none,
                            color: plum,
                          ),
                          title: Text(
                            reminder['reason'] as String? ?? 'Your reminder',
                          ),
                          subtitle: Text(
                            '${_reminderTime(reminder)} · Scheduled',
                          ),
                          onTap: () => notificationHistory(context, c),
                        ),
                    ],
                  ),
                ),
              ],
              if (events.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text(
                  'Things you mentioned',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Panel(
                  child: Column(
                    children: [
                      for (final event in events)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.event_outlined,
                            color: plum,
                          ),
                          title: Text(event['content'] as String),
                          subtitle: Text('${event['date']} · Your plan'),
                          onTap: talk,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: settings,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Your preferences, privacy and check-ins'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _reminderTime(Map reminder) {
    final local = reminder['local_time'] as String?,
        zone = reminder['timezone'] as String?;
    if (local != null && zone != null) {
      return '${local.replaceFirst('T', ' ').substring(0, 16)} $zone';
    }
    final due = DateTime.tryParse(reminder['due_at'] as String? ?? '');
    if (due == null) return 'Time unavailable';
    return '${due.toUtc().toIso8601String().replaceFirst('T', ' ').substring(0, 16)} UTC';
  }
}
