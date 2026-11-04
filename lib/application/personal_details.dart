import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../data/models.dart';
import 'actions.dart';
import 'theme.dart';
import 'account_dialog.dart';
import 'personalization.dart';
import 'timezone_field.dart';

Future<void> editPersonalDetails(
  BuildContext context,
  CompanionController controller,
) async {
  final p = controller.personalProfile;
  final fields = [
    p.preferredName,
    p.displayName,
    p.timezone,
    p.language,
    p.location,
    p.username,
  ].map((v) => TextEditingController(text: v)).toList();
  const labels = [
    'What should I call you?',
    'Full name (optional)',
    'Timezone (for example Africa/Kampala)',
    'Preferred language (optional)',
    'General location (optional)',
    'Username',
  ];
  const limits = [80, 80, 80, 40, 120, 30];
  final form = GlobalKey<FormState>();
  var ageGroup = p.ageGroup;
  var automatic = p.timezoneAutomatic;
  String? value(int i) =>
      fields[i].text.trim().isEmpty ? null : fields[i].text.trim();
  try {
    await showMorrowDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A little about you'),
        content: SizedBox(
          width: 430,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Share only what you like. Your name here takes priority over older conversation memories.',
                  ),
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: i == 2
                          ? TimezoneField(
                              controller: fields[i],
                              automatic: automatic,
                              onAutomaticChanged: (v) => automatic = v,
                            )
                          : TextFormField(
                              controller: fields[i],
                              maxLength: limits[i],
                              decoration: InputDecoration(labelText: labels[i]),
                              validator: (v) =>
                                  i == 5 &&
                                      (widgetNameRequired(controller) ||
                                          (v ?? '').isNotEmpty)
                                  ? usernameError(v)
                                  : i == 0 &&
                                        (widgetNameRequired(controller) ||
                                            fields[5].text.trim().isNotEmpty)
                                  ? preferredNameError(v)
                                  : null,
                            ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: ageGroup,
                    decoration: const InputDecoration(
                      labelText: 'Age range · 18 and older',
                    ),
                    items: [
                      for (final item in ageGroups.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                    ],
                    onChanged: (value) => ageGroup = value,
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
            label: 'Save my details',
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              if (await perform(context, controller, () async {
                    await controller.savePersonalProfile(
                      PersonalProfile(
                        preferredName: value(0),
                        displayName: value(1),
                        timezone: value(2),
                        language: value(3),
                        location: value(4),
                        username: value(5),
                      ),
                    );
                    if (ageGroup != null &&
                        value(2) != null &&
                        value(3) != null) {
                      await controller.saveIntroduction(
                        ageGroup: ageGroup,
                        language: value(3)!,
                        timezone: value(2)!,
                        automatic: automatic,
                      );
                    }
                  }) &&
                  context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  } finally {
    for (final field in fields) {
      field.dispose();
    }
  }
}

bool widgetNameRequired(CompanionController controller) =>
    controller.registeredAccount;
