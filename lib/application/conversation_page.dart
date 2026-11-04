import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/companion_controller.dart';
import '../data/models.dart';
import 'actions.dart';
import 'theme.dart';
import 'reminders.dart';
import 'voice_composer.dart';
import 'report_dialog.dart';
import '../voice/voice_controller.dart';

Future<void> editConversation(
  BuildContext context,
  CompanionController controller,
  Conversation conversation,
) async {
  final input = TextEditingController(text: conversation.title);
  try {
    await showMorrowDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this moment'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ActionButton(
            label: 'Save name',
            onPressed: () async {
              if (input.text.trim().isEmpty) return;
              if (await perform(
                    context,
                    controller,
                    () => controller.renameConversation(
                      conversation.id,
                      input.text.trim(),
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
    input.dispose();
  }
}

Future<void> showHistory(
  BuildContext context,
  CompanionController controller,
  VoidCallback opened,
) async {
  await controller.loadConversations();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Little moments',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: controller.sending
                          ? null
                          : () {
                              controller.newConversation();
                              Navigator.pop(context);
                              opened();
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: controller.conversations.isEmpty
                    ? const Center(
                        child: Text('Your conversations will appear here.'),
                      )
                    : ListView.builder(
                        itemCount: controller.conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = controller.conversations[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.chat_bubble_outline,
                              color: plum,
                            ),
                            title: Text(conversation.title),
                            selected:
                                controller.activeConversation?.id ==
                                conversation.id,
                            onTap: controller.sending
                                ? null
                                : () async {
                                    await controller.openConversation(
                                      conversation,
                                    );
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      opened();
                                    }
                                  },
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Manage conversation',
                              onSelected: (action) async {
                                if (action == 'rename') {
                                  await editConversation(
                                    context,
                                    controller,
                                    conversation,
                                  );
                                } else if (await confirmAction(
                                  context,
                                  title: 'Delete this moment?',
                                  description: 'Its saved messages will be removed. Saved memories are managed separately.',
                                  action: 'Delete',
                                )) {
                                  if (context.mounted) {
                                    await perform(
                                      context,
                                      controller,
                                      () => controller.deleteConversation(
                                        conversation.id,
                                      ),
                                    );
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.controller,
    required this.deviceOnly,
    required this.voice,
    required this.connect,
    this.audio,
  });
  final CompanionController controller;
  final bool deviceOnly;
  final VoidCallback voice, connect;
  final VoiceController? audio;
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _draft.text.trim();
    if (value.isEmpty ||
        widget.controller.sending ||
        widget.controller.loadingConversation ||
        (widget.audio?.hasRecording ?? false) ||
        widget.audio?.stage == VoiceStage.recording ||
        widget.audio?.stage == VoiceStage.transcribing) {
      return;
    }
    _draft.clear();
    await widget.controller.send(value);
    if (widget.controller.error == null &&
        widget.controller.personalProfile.replyMode == 'voice') {
      await widget.audio?.speakReply();
    }
    if (mounted &&
        widget.controller.error != null &&
        widget.controller.retryContent == null) {
      _draft.text = value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller, messages = widget.controller.messages;
    final companion = controller.companion!;
    final audioBusy =
        controller.loadingConversation ||
        widget.audio?.hasRecording == true ||
        widget.audio?.stage == VoiceStage.recording ||
        widget.audio?.stage == VoiceStage.transcribing;
    return LayoutBuilder(
      builder: (context, space) {
        final compact = space.maxHeight < 420;
        return Column(
          children: [
            if (space.maxHeight >= 220)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.activeConversation?.title ??
                                (widget.deviceOnly
                                    ? 'A little moment'
                                    : 'A little conversation'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (!compact)
                            Text(
                              widget.deviceOnly
                                  ? 'Your private journal on this device'
                                  : 'With ${companion.name}, your AI companion',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Conversation history',
                      onPressed: controller.sending || audioBusy
                          ? null
                          : () => showHistory(context, controller, () {}),
                      icon: const Icon(Icons.history_outlined),
                    ),
                    IconButton(
                      tooltip: 'New conversation',
                      onPressed: controller.sending || audioBusy
                          ? null
                          : controller.newConversation,
                      icon: const Icon(Icons.add_comment_outlined),
                    ),
                    IconButton(
                      tooltip: 'Set a reminder',
                      onPressed: widget.deviceOnly
                          ? null
                          : () => reminderDialog(context, controller),
                      icon: const Icon(Icons.notifications_none, color: plum),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (widget.deviceOnly && !compact)
              Container(
                color: lilac.withValues(alpha: .55),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note, size: 20, color: plum),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Save your thoughts here. AI replies become available when your account is connected.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.connect,
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: controller.loadingConversation && messages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : messages.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const LumiOrb(size: 76),
                            const SizedBox(height: 25),
                            Text(
                              'No perfect words needed.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 9),
                            Text(
                              widget.deviceOnly
                                  ? 'A thought, a small win, something you want to remember.'
                                  : 'Tell me a little about your day, or we can simply begin here.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: mutedInk),
                            ),
                          ],
                        ),
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.extentAfter < 100) {
                          unawaited(controller.loadOlderMessages());
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 24,
                        ),
                        itemCount:
                            messages.length + (controller.loadingOlder ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final message = messages[messages.length - 1 - index];
                          return _Message(
                            message: message,
                            name: companion.name,
                            retry: () => controller.retrySend(),
                            report:
                                !widget.deviceOnly &&
                                    !controller.sending &&
                                    !controller.loadingConversation
                                ? () =>
                                      reportReply(context, controller, message)
                                : null,
                            speak:
                                !widget.deviceOnly &&
                                    controller.welcomeAudioAvailable &&
                                    widget.audio != null &&
                                    !controller.sending &&
                                    !audioBusy
                                ? () => widget.audio!.speakReply(message.id)
                                : null,
                          );
                        },
                      ),
                    ),
            ),
            if (!widget.deviceOnly)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (space.maxHeight * .45).clamp(60, 340),
                ),
                child: SingleChildScrollView(
                  child: VoiceComposer(
                    controller: controller,
                    voice: widget.audio,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter, control: true):
                      ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.enter, meta: true):
                      ActivateIntent(),
                },
                child: Actions(
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        unawaited(_send());
                        return null;
                      },
                    ),
                  },
                  child: Focus(
                    skipTraversal: true,
                    onKeyEvent: (_, event) {
                      final desktop = switch (Theme.of(context).platform) {
                        TargetPlatform.windows ||
                        TargetPlatform.linux ||
                        TargetPlatform.macOS => true,
                        _ => false,
                      };
                      final keyboard = HardwareKeyboard.instance;
                      final composing = _draft.value.composing;
                      if (!desktop ||
                          (event.logicalKey != LogicalKeyboardKey.enter &&
                              event.logicalKey !=
                                  LogicalKeyboardKey.numpadEnter) ||
                          keyboard.isShiftPressed ||
                          keyboard.isControlPressed ||
                          keyboard.isMetaPressed ||
                          keyboard.isAltPressed ||
                          (composing.isValid && !composing.isCollapsed)) {
                        return KeyEventResult.ignored;
                      }
                      if (event is KeyDownEvent) unawaited(_send());
                      // Holding Enter must not send again or insert a newline.
                      return KeyEventResult.handled;
                    },
                    child: TextField(
                      key: const ValueKey('message-input'),
                      controller: _draft,
                      minLines: 1,
                      maxLines: compact ? 2 : 5,
                      maxLength: 12000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: widget.deviceOnly
                            ? 'A thought to keep…'
                            : 'Tell me what’s on your mind…',
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(6),
                          child: IconButton.filled(
                            tooltip: widget.deviceOnly
                                ? 'Save thought'
                                : 'Send message',
                            onPressed:
                                controller.sending ||
                                    controller.loadingConversation ||
                                    audioBusy
                                ? null
                                : _send,
                            icon: controller.sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(left: 22, right: 22, bottom: 12),
                child: Text(
                  widget.deviceOnly
                      ? 'Only your own words are saved here. Your device workspace is separate from cloud conversations.'
                      : '${companion.name} is AI. A little company, not a replacement for your people.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.message,
    required this.name,
    required this.retry,
    this.speak,
    this.report,
  });
  final ChatMessage message;
  final String name;
  final Future<void> Function() retry;
  final Future<void> Function()? speak;
  final Future<void> Function()? report;
  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: user ? 560 : 760),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: user
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!user)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '✧ ${name.toUpperCase()}',
                    style: const TextStyle(
                      color: plum,
                      fontSize: 11,
                      letterSpacing: .6,
                    ),
                  ),
                ),
              Container(
                padding: user
                    ? const EdgeInsets.symmetric(horizontal: 19, vertical: 15)
                    : EdgeInsets.zero,
                decoration: user
                    ? BoxDecoration(
                        color: lilac,
                        borderRadius: BorderRadius.circular(22),
                      )
                    : null,
                child: message.content.isEmpty && message.pending
                    ? const Text(
                        'A little thought…',
                        style: TextStyle(color: mutedInk),
                      )
                    : SelectableText(
                        message.content,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
              ),
              if (message.failed && message.turnKind == 'proactive')
                const Text(
                  'This check-in could not be prepared. You can continue the conversation below.',
                ),
              if (message.failed && message.turnKind != 'proactive')
                TextButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    user ? 'Try saving again' : 'Try this message again',
                  ),
                ),
              if (!message.pending && message.content.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!user && !message.failed && report != null)
                      PopupMenuButton<String>(
                        tooltip: 'More reply options',
                        onSelected: (_) => report!(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'report',
                            child: Text('Report reply'),
                          ),
                        ],
                        icon: const Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: mutedInk,
                        ),
                      ),
                    if (!user && !message.failed && speak != null)
                      IconButton(
                        tooltip: 'Play voice reply',
                        visualDensity: VisualDensity.compact,
                        onPressed: speak,
                        icon: const Icon(
                          Icons.volume_up_outlined,
                          size: 17,
                          color: mutedInk,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Copy message',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: message.content),
                        );
                        if (context.mounted) showMessage(context, 'Copied.');
                      },
                      icon: const Icon(
                        Icons.copy_outlined,
                        size: 15,
                        color: mutedInk,
                      ),
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
