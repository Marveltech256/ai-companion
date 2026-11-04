import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../core/app_failure.dart';
import 'actions.dart';

Future<bool> reviewGuestDialog(
  BuildContext context,
  CompanionController controller, {
  bool reauthenticate = false,
}) async {
  final code = TextEditingController();
  var busy = false;
  String? error;
  try {
    return await showMorrowDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) {
              Future<void> enter() async {
                if (busy || code.text.trim().isEmpty) return;
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  await controller.enterReviewGuest(
                    code.text,
                    reauthenticate: reauthenticate,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (failure) {
                  if (context.mounted) {
                    setState(() {
                      busy = false;
                      error = failure is AppFailure ? failure.message : 'Review access could not be opened. Please try again.';
                    });
                  }
                }
              }

              return PopScope(
                canPop: !busy,
                child: AlertDialog(
                  title: Text(
                    reauthenticate
                        ? 'Confirm guest access'
                        : 'Guest for app review',
                  ),
                  content: SizedBox(
                    width: 400,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enter the private code supplied in Play Console. This opens a separate temporary workspace. Use fictional details during testing.',
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: code,
                            enabled: !busy,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Review access code',
                            ),
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => enter(),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : enter,
                      child: Text(
                        busy
                            ? 'Opening…'
                            : reauthenticate
                            ? 'Confirm'
                            : 'Continue as guest',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ) ??
        false;
  } finally {
    code.dispose();
  }
}
