import 'account_dialog.dart';
export 'account_dialog.dart' show accountDialog;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/companion_controller.dart';
import '../data/models.dart';
import '../privacy/export_stub.dart'
    if (dart.library.js_interop) '../privacy/export_web.dart'
    as exporting;
import 'actions.dart';
import 'theme.dart';
import 'personal_details.dart';
import 'reminders.dart';
import 'timezone_field.dart';
import '../billing/billing_controller.dart';
import 'membership_dialog.dart';
import 'review_guest_dialog.dart';

Future<void> exportStory(
  BuildContext context,
  CompanionController controller,
) async {
  final owner = controller.userId;
  final data = await controller.exportData();
  if (data == null || !context.mounted || controller.userId != owner) return;
  if (kIsWeb) {
    await exporting.downloadExport(data);
    return;
  }
  await showMorrowDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Your story, to keep'),
      content: const Text(
        'Your export includes your saved conversations, memories, and preferences. Copy it as JSON to save it somewhere you choose.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            if (controller.userId != owner) {
              Navigator.pop(context);
              return;
            }
            await Clipboard.setData(ClipboardData(text: data));
            if (context.mounted) {
              Navigator.pop(context);
              showMessage(context, 'Export copied. Save it somewhere private.');
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy export'),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.deviceOnly,
    required this.connect,
    required this.useDevice,
    this.memories,
    this.billing,
  });
  final CompanionController controller;
  final bool deviceOnly;
  final Future<void> Function() connect;
  final Future<void> Function()? useDevice;
  final VoidCallback? memories;
  final BillingController? billing;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _erase() async {
    if (widget.controller.reviewGuestAccount) {
      if (!await reviewGuestDialog(
            context,
            widget.controller,
            reauthenticate: true,
          ) ||
          !mounted) {
        return;
      }
    }
    final confirmation = TextEditingController();
    try {
      await showMorrowDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            widget.deviceOnly
                ? 'Remove this device workspace?'
                : 'Delete your account?',
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.deviceOnly
                        ? 'This removes this device’s companion, journal, and memories. Export anything you want to keep first.'
                        : 'This removes your application data and Firebase account. The process can take a little time. Export anything you want to keep first.',
                  ),
                  const SizedBox(height: 18),
                  const Text('Type DELETE_MY_ACCOUNT to confirm.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmation,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirmation',
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
              label: 'Delete permanently',
              onPressed: () async {
                if (confirmation.text != 'DELETE_MY_ACCOUNT') {
                  showMessage(
                    context,
                    'Type DELETE_MY_ACCOUNT exactly to confirm.',
                  );
                  return;
                }
                final ok = await perform(
                  context,
                  widget.controller,
                  () => widget.controller.requestAccountErasure(
                    confirmation.text,
                  ),
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    } finally {
      confirmation.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller,
        companion = widget.controller.companion!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                'Your settings.',
                'A companion that feels a little more like you.',
              ),
              _Section(
                title: 'A gentle hello',
                icon: Icons.notifications_none,
                children: [
                  Text(
                    widget.deviceOnly
                        ? 'Connect a cloud account to schedule and receive check-ins.'
                        : 'Only when you invite one. Choose your time, days, and quiet hours.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.deviceOnly
                        ? widget.connect
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _ScheduleDialog(controller: controller),
                          ),
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      widget.deviceOnly
                          ? 'Connect account'
                          : 'Set check-in schedule',
                    ),
                  ),
                  if (controller.notificationPreferences.enabled) ...[
                    const SizedBox(height: 10),
                    Text(
                      'On · ${controller.notificationPreferences.timezone} · ${_timeLabel(context, controller.notificationPreferences.localMinute)}',
                      style: const TextStyle(color: mutedInk),
                    ),
                  ],
                  if (!widget.deviceOnly)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => reminderDialog(context, controller),
                          icon: const Icon(Icons.add_alarm),
                          label: const Text('Add reminder'),
                        ),
                        TextButton.icon(
                          onPressed: () => perform(
                            context,
                            controller,
                            () => notificationHistory(context, controller),
                          ),
                          icon: const Icon(Icons.history),
                          label: const Text('Reminders & notification history'),
                        ),
                      ],
                    ),
                ],
              ),
              _Section(
                title: 'Voice',
                icon: Icons.graphic_eq,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Spoken greetings'),
                    subtitle: const Text(
                      'Allow optional welcome audio when available. Sound starts only when you press Play. Live calling in Talk is coming soon.',
                    ),
                    value: companion.voiceEnabled,
                    onChanged: (value) => perform(
                      context,
                      controller,
                      () => controller.setVoiceEnabled(value),
                    ),
                  ),
                  const Text(
                    'Speech uses the companion voice configured for this app.',
                    style: TextStyle(color: mutedInk, fontSize: 12),
                  ),
                ],
              ),
              _Section(
                title: 'Privacy & your story',
                icon: Icons.verified_user_outlined,
                children: [
                  if (widget.memories != null)
                    TextButton.icon(
                      onPressed: widget.memories,
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('My saved details'),
                    ),
                  const Text(
                    'Your companion remembers and adapts as you talk. This happens in the background, with your information kept in your own account.',
                  ),
                  if (!widget.deviceOnly) ...[
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          final opened = await launchUrl(
                            Uri.https(
                              'ai-personal-companion-privacy.web.app',
                              '/privacy.html',
                            ),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            showMessage(
                              context,
                              'Open ai-personal-companion-privacy.web.app/privacy.html in your browser.',
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            showMessage(
                              context,
                              'The privacy notice could not be opened. Please try again.',
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Privacy notice'),
                    ),
                    const Text(
                      'Configured AI providers process conversations and approved memories. These services can include Google Gemini and OpenAI.',
                      style: TextStyle(color: mutedInk),
                    ),
                    const SizedBox(height: 14),
                  ],
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      'conversation-retention-${companion.conversationRetentionDays}',
                    ),
                    initialValue: companion.conversationRetentionDays ?? 0,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Keep conversations for',
                    ),
                    items: _retentionOptions(
                      companion.conversationRetentionDays,
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        perform(
                          context,
                          controller,
                          () => controller.setConversationRetention(
                            value == 0 ? null : value,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Shortening retention can remove older conversations. Saved memories have their own retention setting.',
                    style: TextStyle(fontSize: 12, color: mutedInk),
                  ),
                  const SizedBox(height: 18),
                  ActionButton(
                    label: controller.exporting
                        ? 'Preparing your story…'
                        : 'Export your story',
                    secondary: true,
                    icon: Icons.download_outlined,
                    onPressed: controller.exporting
                        ? null
                        : () async {
                            await perform(
                              context,
                              controller,
                              () => exportStory(context, controller),
                            );
                          },
                  ),
                  const SizedBox(height: 12),
                  if (!widget.deviceOnly &&
                      controller.supportsEmail &&
                      !controller.anonymousAccount)
                    TextButton.icon(
                      onPressed: () => widget.controller.reviewGuestAccount
                          ? reviewGuestDialog(
                              context,
                              widget.controller,
                              reauthenticate: true,
                            )
                          : accountDialog(
                              context,
                              controller,
                              reauthenticate: true,
                            ),
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text(
                        'Confirm identity for account deletion',
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _erase,
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: Text(
                      widget.deviceOnly
                          ? 'Delete device workspace'
                          : 'Delete account',
                    ),
                  ),
                ],
              ),
              _Section(
                title: 'Your account',
                icon: Icons.person_outline,
                children: [
                  if (controller.reviewGuestAccount)
                    const Text(
                      'Temporary guest for app review. Use fictional details during testing.',
                    ),
                  if (controller.billingAvailable && widget.billing != null)
                    TextButton.icon(
                      onPressed: () =>
                          membershipDialog(context, widget.billing!),
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('Your membership'),
                    ),
                  if (controller.personalProfile.username != null)
                    Text(
                      '@${controller.personalProfile.username}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  TextButton.icon(
                    onPressed: () => editPersonalDetails(context, controller),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      controller.personalProfile.preferredName == null
                          ? 'My name & personal details'
                          : 'My details · ${controller.personalProfile.preferredName}',
                    ),
                  ),
                  Text(
                    widget.deviceOnly
                        ? 'Saved on this device'
                        : controller.accountEmail ?? 'Guest account',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.deviceOnly
                        ? 'Your device workspace stays separate from cloud data. Connecting opens your cloud space; it does not upload your journal automatically.'
                        : controller.anonymousAccount
                        ? 'Add an email and password before signing out if you want to return to this guest account.'
                        : 'Your cloud space follows your account.',
                    style: const TextStyle(color: mutedInk),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (widget.deviceOnly)
                        ActionButton(
                          label: 'Connect cloud account',
                          icon: Icons.cloud_outlined,
                          onPressed: widget.connect,
                        )
                      else ...[
                        if (controller.supportsEmail)
                          OutlinedButton(
                            onPressed: () => accountDialog(context, controller),
                            child: Text(
                              controller.anonymousAccount
                                  ? 'Save or sign in to an account'
                                  : 'Switch account',
                            ),
                          ),
                        OutlinedButton(
                          onPressed: () async {
                            if (await confirmAction(
                              context,
                              title: controller.reviewGuestAccount
                                  ? 'Exit guest?'
                                  : 'Sign out?',
                              description: controller.reviewGuestAccount
                                  ? 'This workspace stays separate from personal accounts. Entering the review code again starts a new guest workspace.'
                                  : controller.anonymousAccount
                                  ? 'This guest account cannot be restored after sign-out unless you have linked an email. Save your account first if you want to return.'
                                  : 'Your cloud data stays with your account.',
                              action: controller.reviewGuestAccount
                                  ? 'Exit guest'
                                  : 'Sign out',
                            )) {
                              if (context.mounted) {
                                await perform(
                                  context,
                                  controller,
                                  controller.signOut,
                                );
                              }
                            }
                          },
                          child: Text(
                            controller.reviewGuestAccount
                                ? 'Exit guest'
                                : 'Sign out',
                          ),
                        ),
                        if (widget.useDevice != null)
                          ActionButton(
                            label: 'Open device workspace',
                            secondary: true,
                            onPressed: widget.useDevice,
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<DropdownMenuItem<int>> _retentionOptions(int? current) => [
  ..._retentionItems,
  if (current != null && !{30, 90, 365}.contains(current))
    DropdownMenuItem(value: current, child: Text('$current days')),
];

const _retentionItems = [
  DropdownMenuItem(value: 0, child: Text('Until I remove them')),
  DropdownMenuItem(value: 30, child: Text('30 days')),
  DropdownMenuItem(value: 90, child: Text('90 days')),
  DropdownMenuItem(value: 365, child: Text('1 year')),
];

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: plum, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

String _timeLabel(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.controller});
  final CompanionController controller;
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _timezone;
  late NotificationPreferences _initial;
  late bool _checkins, _suggestions, _birthdays;
  late int _minute, _quietStart, _quietEnd;
  late Set<int> _days;
  late List<int> _additional;
  late int _maximum;
  late int _inactivityDays;
  @override
  void initState() {
    super.initState();
    _initial = widget.controller.notificationPreferences;
    _timezone = TextEditingController(text: _initial.timezone ?? '');
    _checkins = _initial.checkins;
    _suggestions = _initial.suggestions;
    _birthdays = _initial.birthdays;
    _minute = _initial.localMinute;
    _quietStart = _initial.quietStart;
    _quietEnd = _initial.quietEnd;
    _days = _initial.weekdays.toSet();
    _additional = List.from(_initial.additionalMinutes);
    _maximum = _initial.maxPerDay;
    _inactivityDays = _initial.inactivityDays;
  }

  @override
  void dispose() {
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _pick(int value, void Function(int) save) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    if (time != null && mounted) {
      setState(() => save(time.hour * 60 + time.minute));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('A hello, on your terms'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose how often you would like a hello. Delivery may be delayed; quiet hours and your saved work or sleep boundaries apply.',
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gentle check-ins'),
                value: _checkins,
                onChanged: (value) => setState(() => _checkins = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activity suggestions'),
                value: _suggestions,
                onChanged: (value) => setState(() => _suggestions = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Important-date reminders'),
                subtitle: const Text('Only dates you explicitly schedule.'),
                value: _birthdays,
                onChanged: (value) => setState(() => _birthdays = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _inactivityDays,
                decoration: const InputDecoration(
                  labelText: 'When to check in',
                ),
                items: [
                  for (final days in {
                    0,
                    1,
                    2,
                    3,
                    7,
                    14,
                    _inactivityDays,
                  }.toList()..sort())
                    DropdownMenuItem(
                      value: days,
                      child: Text(
                        days == 0
                            ? 'At my selected times'
                            : 'After $days ${days == 1 ? 'day' : 'days'} without chatting',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _inactivityDays = value;
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'After an inactivity check-in, we wait for your reply before sending another. Reminders you schedule remain separate.',
              ),
              const SizedBox(height: 14),
              TimezoneField(
                controller: _timezone,
                requiredValue: _checkins || _suggestions || _birthdays,
              ),
              const SizedBox(height: 16),
              const Text('Days'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(
                        const [
                          'Sun',
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                        ][i],
                      ),
                      selected: _days.contains(i),
                      onSelected: (value) => setState(() {
                        if (value) {
                          _days.add(i);
                        } else {
                          _days.remove(i);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('A good time for a hello'),
                trailing: TextButton(
                  onPressed: () => _pick(_minute, (value) => _minute = value),
                  child: Text(_timeLabel(context, _minute)),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet hours start'),
                trailing: TextButton(
                  onPressed: () =>
                      _pick(_quietStart, (value) => _quietStart = value),
                  child: Text(_timeLabel(context, _quietStart)),
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: _maximum,
                decoration: const InputDecoration(
                  labelText: 'Maximum notifications per day',
                ),
                items: [
                  for (var n = 1; n <= 3; n++)
                    DropdownMenuItem(value: n, child: Text('$n per day')),
                ],
                onChanged: (v) => setState(() {
                  _maximum = v!;
                  _additional = _additional.take(_maximum - 1).toList();
                }),
              ),
              for (var i = 0; i < _additional.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () =>
                            _pick(_additional[i], (v) => _additional[i] = v),
                        child: Text(
                          'Another hello: ${_timeLabel(context, _additional[i])}',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove check-in time',
                      onPressed: () => setState(() => _additional.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              if (_additional.length < _maximum - 1)
                TextButton.icon(
                  onPressed: () => _pick(_minute, (v) => _additional.add(v)),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a check-in time'),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet hours end'),
                trailing: TextButton(
                  onPressed: () =>
                      _pick(_quietEnd, (value) => _quietEnd = value),
                  child: Text(_timeLabel(context, _quietEnd)),
                ),
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
        label: 'Save schedule',
        onPressed: () async {
          if (!_form.currentState!.validate()) return;
          if (_days.isEmpty || _quietStart == _quietEnd) {
            showMessage(
              context,
              'Choose at least one day and different quiet-hour times.',
            );
            return;
          }
          final insideQuiet = _quietStart < _quietEnd
              ? _minute >= _quietStart && _minute < _quietEnd
              : _minute >= _quietStart || _minute < _quietEnd;
          if ((_checkins || _suggestions || _birthdays) && insideQuiet) {
            showMessage(
              context,
              'Choose a check-in time outside your quiet hours.',
            );
            return;
          }
          final saved = await perform(
            context,
            widget.controller,
            () => widget.controller.saveNotificationPreferences(
              NotificationPreferences(
                checkins: _checkins,
                suggestions: _suggestions,
                birthdays: _birthdays,
                timezone: _timezone.text.trim().isEmpty
                    ? null
                    : _timezone.text.trim(),
                localMinute: _minute,
                weekdays: _days.toList()..sort(),
                quietStart: _quietStart,
                quietEnd: _quietEnd,
                additionalMinutes: _additional,
                maxPerDay: _maximum,
                inactivityDays: _inactivityDays,
              ),
            ),
          );
          if (saved && context.mounted) Navigator.pop(context);
        },
      ),
    ],
  );
}
