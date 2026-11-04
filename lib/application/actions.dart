import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../core/app_failure.dart';

void showMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Keep editor resources alive until the dialog's exit transition has removed
/// its fields from the tree, rather than only until Navigator.pop is called.
Future<T?> showMorrowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}

Future<bool> perform(
  BuildContext context,
  CompanionController controller,
  Future<void> Function() work, {
  String? success,
}) async {
  controller.clearNotice();
  try {
    await work();
    if (controller.error != null) throw controller.error!;
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } catch (error) {
    if (context.mounted) {
      showMessage(
        context,
        error is AppFailure
            ? error.message
            : 'Could not save that change. Please try again.',
      );
    }
    return false;
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String description,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
