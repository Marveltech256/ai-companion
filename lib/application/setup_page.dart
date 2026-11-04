import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import 'theme.dart';
import 'account_dialog.dart';
import 'actions.dart';
import 'personalization.dart';
import 'timezone_field.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({
    super.key,
    required this.controller,
    required this.deviceOnly,
    this.useDevice,
    this.connectCloud,
  });
  final CompanionController controller;
  final bool deviceOnly;
  final Future<void> Function()? useDevice;
  final Future<void> Function()? connectCloud;
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Lumi');
  late final TextEditingController _username, _preferredName;
  late final TextEditingController _timezone;
  String? _age;
  String _language = 'en';
  bool _saving = false;
  bool _timezoneAutomatic = true;
  @override
  void initState() {
    super.initState();
    _username = TextEditingController(
      text: widget.controller.personalProfile.username,
    );
    _preferredName = TextEditingController(
      text: widget.controller.personalProfile.preferredName,
    );
    _timezone = TextEditingController(
      text: widget.controller.personalProfile.timezone,
    );
    _language = storedLanguageChoice(
      widget.controller.personalProfile.language,
    );
    _age = widget.controller.personalProfile.ageGroup;
    _timezoneAutomatic =
        widget.controller.personalProfile.timezone == null ||
        widget.controller.personalProfile.timezoneAutomatic;
  }

  @override
  void didUpdateWidget(covariant SetupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_username.text.isEmpty &&
        widget.controller.personalProfile.username != null) {
      _username.text = widget.controller.personalProfile.username!;
    }
    if (_preferredName.text.isEmpty &&
        widget.controller.personalProfile.preferredName != null) {
      _preferredName.text = widget.controller.personalProfile.preferredName!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _preferredName.dispose();
    _timezone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.controller.needsAccountDetails
      ? _completeProfile(context)
      : widget.controller.companion != null && !widget.deviceOnly
      ? _existingIntroduction(context)
      : Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 26,
                  ),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: Brand()),
                        const SizedBox(height: 32),
                        const Center(child: LumiOrb(size: 86)),
                        const SizedBox(height: 32),
                        Text(
                          'A friend, in your own way.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'An AI companion shaped by you. Start with a name and a little of your world.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: mutedInk),
                        ),
                        const SizedBox(height: 28),
                        if (!widget.deviceOnly) ...[
                          DropdownButtonFormField<String>(
                            key: const ValueKey('introduction-age'),
                            initialValue: _age,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Age range · 18 and older',
                            ),
                            validator: (value) => value == null
                                ? 'Choose your age range. This app is for ages 18+.'
                                : null,
                            items: [
                              for (final entry in ageGroups.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: (value) =>
                                _age = value == '' ? null : value,
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: const ValueKey('introduction-language'),
                            initialValue: _language,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Conversation language',
                            ),
                            items: [
                              for (final entry in {
                                ...conversationLanguages,
                                if (!conversationLanguages.containsKey(
                                  _language,
                                ))
                                  _language: _language,
                              }.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) _language = value;
                            },
                          ),
                          const SizedBox(height: 14),
                          TimezoneField(
                            key: const ValueKey('introduction-timezone'),
                            controller: _timezone,
                            automatic: _timezoneAutomatic,
                            onAutomaticChanged: (value) =>
                                _timezoneAutomatic = value,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (!widget.deviceOnly &&
                            widget.controller.supportsAccounts &&
                            !widget.controller.registeredAccount) ...[
                          FilledButton(
                            onPressed: widget.controller.busy
                                ? null
                                : () => accountDialog(
                                    context,
                                    widget.controller,
                                    create: true,
                                  ),
                            child: const Text('Create account'),
                          ),
                          TextButton(
                            onPressed: widget.controller.busy
                                ? null
                                : () => accountDialog(
                                    context,
                                    widget.controller,
                                    signInOnly: true,
                                  ),
                            child: const Text(
                              'Sign in or continue with Google',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const Panel(
                          color: lilac,
                          child: Text(
                            'Your companion remembers useful details you share and learns from your conversations. By continuing, you agree to this personal companion experience. You can review your saved details and manage your data in Privacy.',
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (widget.controller.error != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              widget.controller.error!.message,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        ActionButton(
                          label:
                              'Meet ${_name.text.trim().isEmpty ? 'your companion' : _name.text.trim()}',
                          icon: Icons.arrow_forward,
                          onPressed:
                              _saving ||
                                  widget.controller.busy ||
                                  !widget.controller.configured
                              ? null
                              : () async {
                                  if (_form.currentState!.validate()) {
                                    setState(() => _saving = true);
                                    try {
                                      await perform(
                                        context,
                                        widget.controller,
                                        () async {
                                          if (!widget.deviceOnly) {
                                            await widget.controller
                                                .saveIntroduction(
                                                  ageGroup: _age,
                                                  language: _language,
                                                  automatic: _timezoneAutomatic,
                                                  timezone: _timezone.text
                                                      .trim(),
                                                );
                                          }
                                          await widget.controller.create(
                                            name: _name.text.trim(),
                                            style: styles.first,
                                            interests: const [],
                                            memoryEnabled: true,
                                            friendMode: !widget.deviceOnly,
                                          );
                                        },
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => _saving = false);
                                      }
                                    }
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.deviceOnly
                              ? 'Your space is saved on this device. Connect an account later for AI conversations.'
                              : 'Your companion, your pace. Memories are always your choice.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (!widget.deviceOnly && widget.useDevice != null) ...[
                          const SizedBox(height: 14),
                          ActionButton(
                            label: 'Start on this device',
                            secondary: true,
                            onPressed: widget.useDevice,
                          ),
                        ],
                        if (widget.deviceOnly || !widget.controller.configured)
                          TextButton(
                            onPressed: widget.connectCloud,
                            child: const Text('Connect a cloud account'),
                          ),
                        if (!widget.deviceOnly &&
                            widget.controller.supportsEmail)
                          TextButton(
                            onPressed: () => accountDialog(
                              context,
                              widget.controller,
                              signInOnly: true,
                            ),
                            child: const Text(
                              'Already have an account? Sign in',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

  Widget _existingIntroduction(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Brand()),
                  const SizedBox(height: 26),
                  Text(
                    'Before we catch up.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ai Companion is for people aged 18 and older. Choose an age range and how you would like to chat. Your companion and conversations stay here.',
                  ),
                  const SizedBox(height: 22),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('introduction-age'),
                    initialValue: _age,
                    decoration: const InputDecoration(labelText: 'Age range'),
                    validator: (value) =>
                        value == null ? 'Choose your age range.' : null,
                    items: [
                      for (final item in ageGroups.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                    ],
                    onChanged: (value) => _age = value,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('introduction-language'),
                    initialValue: _language,
                    decoration: const InputDecoration(
                      labelText: 'Conversation language',
                    ),
                    items: [
                      for (final item in {
                        ...conversationLanguages,
                        if (!conversationLanguages.containsKey(_language))
                          _language: _language,
                      }.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _language = value;
                    },
                  ),
                  const SizedBox(height: 14),
                  TimezoneField(
                    key: const ValueKey('introduction-timezone'),
                    controller: _timezone,
                    automatic: _timezoneAutomatic,
                    onAutomaticChanged: (value) => _timezoneAutomatic = value,
                  ),
                  const SizedBox(height: 22),
                  ActionButton(
                    label: 'Continue',
                    onPressed: _saving
                        ? null
                        : () async {
                            if (!_form.currentState!.validate()) return;
                            setState(() => _saving = true);
                            try {
                              if (await perform(
                                context,
                                widget.controller,
                                () => widget.controller.saveIntroduction(
                                  ageGroup: _age,
                                  language: _language,
                                  automatic: _timezoneAutomatic,
                                  timezone: _timezone.text.trim(),
                                ),
                              )) {
                                await widget.controller.loadConversations();
                                await widget.controller.loadHomeActivity();
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                  ),
                  TextButton(
                    onPressed: widget.controller.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _completeProfile(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Brand()),
                  const SizedBox(height: 32),
                  const Center(child: LumiOrb(size: 86)),
                  const SizedBox(height: 28),
                  Text(
                    'Make this space yours.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choose your username and the name you would like your companion to use.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const ValueKey('profile-username'),
                    controller: _username,
                    maxLength: 30,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: usernameError,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const ValueKey('profile-preferred-name'),
                    controller: _preferredName,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'What should I call you?',
                      hintText: 'For example, Marvin',
                    ),
                    validator: preferredNameError,
                  ),
                  if (widget.controller.error != null)
                    Text(
                      widget.controller.error!.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 18),
                  ActionButton(
                    label: 'Save my name',
                    onPressed: widget.controller.busy
                        ? null
                        : () async {
                            if (_form.currentState!.validate()) {
                              await perform(
                                context,
                                widget.controller,
                                () => widget.controller.completeAccountDetails(
                                  _username.text,
                                  _preferredName.text,
                                ),
                              );
                            }
                          },
                  ),
                  TextButton(
                    onPressed: widget.controller.busy
                        ? null
                        : widget.controller.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
