import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../data/models.dart';
import 'actions.dart';
import 'theme.dart';
import 'memory_details.dart';
import 'reminders.dart';

String categoryLabel(String category) => canonicalMemoryCategory(category)
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

String memorySummary(BuildContext context, Map<String, dynamic> a) {
  String time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);
  final days = List<int>.from(a['weekdays'] as List? ?? []);
  return [
    if (a['value'] != null) a['value'].toString(),
    if (days.isNotEmpty)
      days
          .map(
            (d) => const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d],
          )
          .join(', '),
    if (a['start_minute'] is int) 'Starts ${time(a['start_minute'] as int)}',
    if (a['end_minute'] is int) 'Ends ${time(a['end_minute'] as int)}',
    if (a['annual'] == true)
      'Every year: ${a['day']}/${a['month']}'
    else if (a['on_date'] != null)
      a['on_date'].toString(),
    if (a['skip'] == true) 'Day off / exception',
    if (a['block_notifications'] == true)
      'No interruptions during this activity',
    if (a['timezone'] != null) a['timezone'].toString(),
  ].join(' · ');
}

Future<void> editMemory(
  BuildContext context,
  CompanionController controller, [
  CompanionMemory? memory,
]) async {
  final title = TextEditingController(text: memory?.title),
      content = TextEditingController(text: memory?.content);
  final form = GlobalKey<FormState>();
  var category = canonicalMemoryCategory(memory?.category ?? 'preferences');
  final attributes = Map<String, dynamic>.from(memory?.attributes ?? {})
    ..remove('observed_at')
    ..remove('relative_days');
  DateTime? expiry = memory?.expiresAt;
  try {
    await showMorrowDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            memory == null ? 'A little thing to remember' : 'Edit this memory',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: title,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Add a title.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: content,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'What would you like to keep?',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Write something to remember.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      isExpanded: true,
                      items: [
                        for (final item in memoryCategories)
                          DropdownMenuItem(
                            value: item,
                            child: Text(categoryLabel(item)),
                          ),
                      ],
                      onChanged: (value) => update(() {
                        category = value!;
                        attributes.clear();
                      }),
                    ),
                    const SizedBox(height: 14),
                    MemoryDetails(
                      key: ValueKey(category),
                      category: category,
                      attributes: attributes,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            expiry == null
                                ? 'No individual expiry date'
                                : 'Forget after ${expiry!.day}/${expiry!.month}/${expiry!.year}',
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final now = DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  expiry != null && expiry!.isAfter(now)
                                  ? expiry
                                  : now.add(const Duration(days: 30)),
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: now.add(const Duration(days: 3650)),
                            );
                            if (date != null) {
                              update(
                                () => expiry = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  23,
                                  59,
                                ),
                              );
                            }
                          },
                          child: const Text('Set date'),
                        ),
                        if (expiry != null)
                          IconButton(
                            tooltip: 'Remove expiry',
                            onPressed: () => update(() => expiry = null),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ActionButton(
              label: 'Save memory',
              icon: Icons.check,
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final saved = await perform(
                  context,
                  controller,
                  () => controller.saveMemory(
                    id: memory?.id,
                    category: category,
                    title: title.text.trim(),
                    content: content.text.trim(),
                    expiresAt: expiry,
                    attributes: attributes,
                  ),
                );
                if (saved && context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  } finally {
    title.dispose();
    content.dispose();
  }
}

class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key, required this.controller});
  final CompanionController controller;
  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  final _search = TextEditingController();
  String? _category;
  @override
  void initState() {
    super.initState();
    widget.controller.loadMemories();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final records = widget.controller.memories
        .where(
          (memory) =>
              (_category == null ||
                  canonicalMemoryCategory(memory.category) == _category) &&
              '${memory.title} ${memory.content}'.toLowerCase().contains(query),
        )
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1060),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(
                'The little things, remembered.',
                'Your story belongs to you. Keep, change, or let go.',
                action: FilledButton.icon(
                  onPressed: () => editMemory(context, widget.controller),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add memory'),
                ),
              ),
              TextField(
                key: const ValueKey('memory-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Find a memory…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final category in memoryCategories)
                    ChoiceChip(
                      label: Text(categoryLabel(category)),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (records.isEmpty)
                Panel(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.menu_book_outlined,
                          color: plum,
                          size: 34,
                        ),
                        const SizedBox(height: 15),
                        Text(
                          query.isEmpty && _category == null
                              ? 'Room for your story.'
                              : 'No memories found.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          query.isEmpty && _category == null
                              ? 'Add a detail you would like to keep, in your own words.'
                              : 'Try another word or category.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: mutedInk),
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, box) {
                    final columns = box.maxWidth >= 760
                        ? 3
                        : box.maxWidth >= 500
                        ? 2
                        : 1;
                    final width = (box.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final memory in records)
                          SizedBox(
                            width: width,
                            child: _MemoryCard(
                              memory: memory,
                              controller: widget.controller,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 24),
              Panel(
                color: lilac.withValues(alpha: .5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: plum,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Memory is your choice.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: plum,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.controller.companion!.memoryEnabled
                                ? 'Automatic memory is on. You can pause it in Our rhythm.'
                                : 'Automatic memory is paused. You can still add and manage memories yourself.',
                            style: const TextStyle(color: mutedInk),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Forgetting a memory does not remove its original conversation.',
                            style: TextStyle(fontSize: 12, color: mutedInk),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory, required this.controller});
  final CompanionMemory memory;
  final CompanionController controller;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bookmark_border, color: plum, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                categoryLabel(memory.category),
                style: const TextStyle(fontSize: 11, color: mutedInk),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Manage ${memory.title}',
              onSelected: (value) async {
                if (value == 'edit') {
                  await editMemory(context, controller, memory);
                } else if (value == 'remind') {
                  await reminderDialog(context, controller, memory);
                } else if (await confirmAction(
                  context,
                  title: 'Forget this memory?',
                  description: 'This detail will be removed from saved memory. Its original conversation stays in your history.',
                  action: 'Forget',
                )) {
                  if (context.mounted) {
                    await perform(
                      context,
                      controller,
                      () => controller.forgetMemory(memory.id),
                    );
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit memory')),
                if (!controller.journalOnly)
                  const PopupMenuItem(
                    value: 'remind',
                    child: Text('Set a reminder'),
                  ),
                const PopupMenuItem(
                  value: 'forget',
                  child: Text('Forget memory'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(memory.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SelectableText(
          memory.content,
          style: const TextStyle(color: mutedInk, height: 1.6),
        ),
        if (memory.sourceQuote != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'From you: ${memory.sourceQuote}',
              style: const TextStyle(fontSize: 12, color: mutedInk),
            ),
          ),
        if (memory.attributes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              memorySummary(context, memory.attributes),
              style: const TextStyle(fontSize: 12, color: mutedInk),
            ),
          ),
        Text(
          '${memory.verification == 'user_confirmed'
              ? 'Confirmed by you'
              : memory.verification == 'unverified'
              ? 'Needs confirmation'
              : 'From your conversation'} · ${memory.temporalStatus}${memory.confidence == null ? '' : ' · ${(memory.confidence! * 100).round()}% confidence'}',
          style: const TextStyle(fontSize: 11, color: mutedInk),
        ),
        const SizedBox(height: 18),
        if (memory.createdAt != null)
          Text(
            'Added ${memory.createdAt!.toLocal().day}/${memory.createdAt!.toLocal().month}/${memory.createdAt!.toLocal().year}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Text(
          'Kept ${memory.updatedAt.toLocal().day}/${memory.updatedAt.toLocal().month}/${memory.updatedAt.toLocal().year}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (memory.expiresAt != null)
          Text(
            'Forgets ${memory.expiresAt!.toLocal().day}/${memory.expiresAt!.toLocal().month}/${memory.expiresAt!.toLocal().year}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}
