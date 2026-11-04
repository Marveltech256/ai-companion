import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../app/companion_controller.dart';
import '../data/models.dart';
import 'actions.dart';

Future<void> reportReply(
  BuildContext context,
  CompanionController controller,
  ChatMessage message,
) async {
  final note = TextEditingController();
  final request = const Uuid().v4(), owner = controller.userId;
  var reason = 'unsafe', saving = false;
  try {
    await showMorrowDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Report this reply'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Send this reply and your optional note to the Ai Companion team for review. Your other messages are not included.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: const [
                      DropdownMenuItem(
                        value: 'unsafe',
                        child: Text('Unsafe or offensive'),
                      ),
                      DropdownMenuItem(
                        value: 'inaccurate',
                        child: Text('Inaccurate or misleading'),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text('Something else'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => update(() => reason = value!),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: note,
                    enabled: !saving,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Anything to add? (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (controller.userId != owner) return;
                      update(() => saving = true);
                      final ok = await perform(
                        dialog,
                        controller,
                        () => controller.reportMessage(
                          messageId: message.id,
                          requestId: request,
                          reason: reason,
                          details: note.text.trim(),
                        ),
                      );
                      if (!dialog.mounted) return;
                      if (ok && controller.userId == owner) {
                        Navigator.pop(dialog);
                        if (context.mounted) {
                          showMessage(
                            context,
                            'Report received. Thank you for letting us know.',
                          );
                        }
                      } else {
                        update(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Sending…' : 'Send report'),
            ),
          ],
        ),
      ),
    );
  } finally {
    note.dispose();
  }
}
