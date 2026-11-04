import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app/companion_controller.dart';
import '../data/models.dart';
import 'actions.dart';
import 'theme.dart';

Future<void> reminderDialog(
  BuildContext context,
  CompanionController controller, [
  CompanionMemory? memory,
]) async {
  if (controller.journalOnly ||
      !controller.notificationPreferences.birthdays ||
      controller.notificationPreferences.timezone == null) {
    showMessage(
      context,
      'Enable important-date reminders and choose a schedule in Your settings first.',
    );
    return;
  }
  final userMessages = controller.messages.where(
    (m) => m.role == 'user' && !m.pending && !m.failed,
  );
  final recent = userMessages.isEmpty ? null : userMessages.last.content;
  final reason = TextEditingController(
    text:
        memory?.content ??
        (recent != null && recent.length <= 2000 ? recent : null),
  );
  final requestId = const Uuid().v4();
  DateTime? day = DateTime.tryParse(
    memory?.attributes['on_date'] as String? ?? '',
  );
  TimeOfDay? time;
  try {
    await showMorrowDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('A reminder, when you choose'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Times use ${controller.notificationPreferences.timezone}. Your quiet hours, days, routines, and daily limit apply.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reason,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'What would you like to remember?',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: day != null && day!.isAfter(now)
                            ? day
                            : now,
                        firstDate: now.subtract(const Duration(days: 1)),
                        lastDate: now.add(const Duration(days: 366)),
                      );
                      if (picked != null) update(() => day = picked);
                    },
                    child: Text(
                      day == null
                          ? 'Choose a date'
                          : '${day!.year}-${day!.month.toString().padLeft(2, '0')}-${day!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: time ?? TimeOfDay.now(),
                      );
                      if (picked != null) update(() => time = picked);
                    },
                    child: Text(
                      time == null ? 'Choose a time' : time!.format(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ActionButton(
              label: 'Schedule reminder',
              onPressed: () async {
                if (day == null || time == null || reason.text.trim().isEmpty) {
                  showMessage(context, 'Choose a date, time, and reminder.');
                  return;
                }
                final local = DateTime(
                  day!.year,
                  day!.month,
                  day!.day,
                  time!.hour,
                  time!.minute,
                ).toIso8601String().substring(0, 16);
                if (await perform(
                      context,
                      controller,
                      () => controller.scheduleReminder(
                        requestId: requestId,
                        reason: reason.text.trim(),
                        localTime: local,
                        source: memory?.id,
                      ),
                      success:
                          'Reminder queued. Delivery is not confirmed yet.',
                    ) &&
                    context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  } finally {
    reason.dispose();
  }
}

Future<void> notificationHistory(
  BuildContext context,
  CompanionController controller,
) async {
  var rows = await controller.checkinHistory();
  final owner = controller.userId;
  if (!context.mounted) return;
  await showMorrowDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Your reminders & check-ins'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: rows.isEmpty
              ? const Center(child: Text('No reminders or check-ins yet.'))
              : ListView(
                  children: [
                    for (final row in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          row['reason'] as String? ?? 'Scheduled check-in',
                        ),
                        subtitle: Text(
                          '${row['due_at']}\n${row['opened_at'] != null
                              ? 'Opened in app'
                              : row['received_at'] != null
                              ? 'Received in app'
                              : row['provider_accepted_at'] != null
                              ? 'Accepted by provider; delivery unconfirmed'
                              : row['status']}\n${row['outcome_detail'] ?? ''}',
                        ),
                        trailing: {'queued', 'sending'}.contains(row['status'])
                            ? IconButton(
                                tooltip: 'Cancel reminder',
                                icon: const Icon(Icons.close),
                                onPressed: () async {
                                  if (controller.userId != owner) {
                                    Navigator.pop(context);
                                    return;
                                  }
                                  if (await perform(
                                    context,
                                    controller,
                                    () => controller.cancelCheckin(
                                      row['id'] as String,
                                    ),
                                  )) {
                                    rows = await controller.checkinHistory();
                                    if (context.mounted) update(() {});
                                  }
                                },
                              )
                            : null,
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
