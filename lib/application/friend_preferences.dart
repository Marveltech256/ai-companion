import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../data/models.dart';
import 'actions.dart';
import 'theme.dart';

const friendPersonalities = {
  'warm_caring': 'Warm and Caring',
  'funny_playful': 'Funny and Playful',
  'calm_understanding': 'Calm and Understanding',
  'positive_motivating': 'Positive and Motivating',
  'curious_intellectual': 'Curious and Intellectual',
  'friendly_outgoing': 'Friendly and Outgoing',
  'wise_thoughtful': 'Wise and Thoughtful',
  'casual_relaxed': 'Casual and Relaxed',
};
const friendSupport = {
  'emotional_support': 'Emotional Support',
  'daily_companionship': 'Daily Companionship',
  'motivation': 'Motivation and Encouragement',
  'personal_growth': 'Personal Growth',
  'learning': 'Learning and Knowledge',
  'friendship': 'Friendship and Conversation',
  'productivity': 'Productivity and Organization',
  'perspectives': 'Life Advice and Different Perspectives',
  'creativity': 'Creativity and Ideas',
  'relaxation': 'Entertainment and Relaxation',
  'language_practice': 'Language Practice',
  'confidence': 'Confidence and Communication',
};
const friendCommunication = {
  'casual_natural': 'Casual and natural',
  'warm_affectionate': 'Warm and affectionate',
  'calm_gentle': 'Calm and gentle',
  'funny_playful': 'Funny and playful',
  'direct': 'Direct and straightforward',
  'thoughtful_detailed': 'Thoughtful and detailed',
};
const _personalityDescriptions = {
  'warm_caring': 'Thoughtful listening and kindness.',
  'funny_playful': 'Humour, jokes and lighthearted conversation.',
  'calm_understanding': 'Patient listening and gentle communication.',
  'positive_motivating': 'Encouragement and celebrating your progress.',
  'curious_intellectual': 'Ideas, knowledge and exploring new things.',
  'friendly_outgoing': 'Lively conversation about everyday life.',
  'wise_thoughtful': 'Reflection and different perspectives.',
  'casual_relaxed': 'Easy conversation without formality.',
};

class FriendPreferencesDraft {
  FriendPreferencesDraft([Companion? companion]) {
    name.text = companion?.name ?? 'Lumi';
    final p = companion?.preferences ?? const CompanionPreferences();
    personalities.addAll(
      p.personalities.where(friendPersonalities.containsKey),
    );
    if (personalities.isEmpty) {
      personalities.add(switch (companion?.style) {
        'Playful' => 'funny_playful',
        'Reflective' => 'wise_thoughtful',
        _ => 'warm_caring',
      });
    }
    support.addAll(p.support.where(friendSupport.containsKey));
    communication = friendCommunication.containsKey(p.communication)
        ? p.communication!
        : 'casual_natural';
    learning.text = p.learning;
    goals.text = p.goals;
    additional.text = p.additional;
  }
  final name = TextEditingController();
  final learning = TextEditingController();
  final goals = TextEditingController();
  final additional = TextEditingController();
  final personalities = <String>{}, support = <String>{};
  String communication = 'casual_natural';
  CompanionPreferences get value => CompanionPreferences(
    personalities: personalities.toList(),
    support: support.toList(),
    communication: communication,
    learning: learning.text.trim(),
    goals: goals.text.trim(),
    additional: additional.text.trim(),
  );
  void dispose() {
    for (final field in [name, learning, goals, additional]) {
      field.dispose();
    }
  }
}

/// Reused by the existing introduction and settings; no separate preference dashboard.
class FriendPreferenceFields extends StatefulWidget {
  const FriendPreferenceFields({super.key, required this.draft, this.step});
  final FriendPreferencesDraft draft;
  final int? step;
  @override
  State<FriendPreferenceFields> createState() => _FriendPreferenceFieldsState();
}

class _FriendPreferenceFieldsState extends State<FriendPreferenceFields> {
  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.step == null || widget.step == 0) ...[
          Text(
            'What would you like to name your new friend?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('companion-name'),
            controller: d.name,
            maxLength: 24,
            decoration: const InputDecoration(labelText: 'Companion’s name'),
            validator: (v) => (v ?? '').trim().isEmpty
                ? 'Choose a name for your friend.'
                : null,
          ),
          const SizedBox(height: 14),
        ],
        if (widget.step == null || widget.step == 1) ...[
          Text(
            'What kind of personality would you like your friend to have?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose one, or blend two.',
            style: TextStyle(color: mutedInk),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in friendPersonalities.entries)
                Tooltip(
                  message: _personalityDescriptions[entry.key]!,
                  child: FilterChip(
                    key: ValueKey('personality-${entry.key}'),
                    label: Text(entry.value),
                    selected: d.personalities.contains(entry.key),
                    onSelected:
                        d.personalities.contains(entry.key) ||
                            d.personalities.length < 2
                        ? (selected) => setState(() {
                            if (selected && d.personalities.length < 2) {
                              d.personalities.add(entry.key);
                            } else if (!selected &&
                                d.personalities.length > 1) {
                              d.personalities.remove(entry.key);
                            }
                          })
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            d.personalities
                .map((key) => _personalityDescriptions[key]!)
                .join(' '),
            style: const TextStyle(color: mutedInk),
          ),
          const SizedBox(height: 24),
          Text(
            'What would you like your friend to be there for?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${d.support.length} of 4 selected · Choose up to four, or skip.',
            key: const ValueKey('support-count'),
            style: const TextStyle(color: mutedInk),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in friendSupport.entries)
                FilterChip(
                  key: ValueKey('support-${entry.key}'),
                  label: Text(entry.value),
                  selected: d.support.contains(entry.key),
                  onSelected:
                      d.support.contains(entry.key) || d.support.length < 4
                      ? (selected) => setState(() {
                          if (selected) {
                            d.support.add(entry.key);
                          } else {
                            d.support.remove(entry.key);
                          }
                        })
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (widget.step == null || widget.step == 2) ...[
          Text(
            'How would you like your friend to communicate with you?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey('friend-communication'),
            initialValue: d.communication,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Communication style'),
            items: [
              for (final entry in friendCommunication.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) d.communication = value;
            },
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const ValueKey('friend-learning'),
            controller: d.learning,
            maxLength: 400,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Learning or practice (optional)',
              hintText: 'For example, German or job interviews',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('friend-goals'),
            controller: d.goals,
            maxLength: 600,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Personal goals (optional)',
              hintText: 'For example, reading more books',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('friend-additional'),
            controller: d.additional,
            maxLength: 600,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Anything else? (optional)',
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> editFriendPreferences(
  BuildContext context,
  CompanionController controller,
) async {
  final draft = FriendPreferencesDraft(controller.companion);
  final form = GlobalKey<FormState>();
  try {
    await showMorrowDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your companion, your way'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: FriendPreferenceFields(draft: draft),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ActionButton(
            label: 'Save companion',
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              if (await perform(
                    context,
                    controller,
                    () => controller.saveFriendPreferences(
                      draft.name.text.trim(),
                      draft.value,
                    ),
                  ) &&
                  context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  } finally {
    draft.dispose();
  }
}
