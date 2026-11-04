import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../voice/voice_controller.dart';
import 'actions.dart';
import 'theme.dart';

class VoiceComposer extends StatefulWidget {
  const VoiceComposer({
    super.key,
    required this.controller,
    required this.voice,
  });
  final CompanionController controller;
  final VoiceController? voice;
  @override
  State<VoiceComposer> createState() => _VoiceComposerState();
}

class _VoiceComposerState extends State<VoiceComposer> {
  final _transcript = TextEditingController();
  String? _source;
  @override
  void dispose() {
    _transcript.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, v = widget.voice;
    final reviewing = v?.stage == VoiceStage.review;
    if (reviewing && v!.caption != _source) {
      _source = v.caption;
      _transcript.text = v.caption;
    }
    final capturing = v?.stage == VoiceStage.recording,
        transcribing = v?.stage == VoiceStage.transcribing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(
                    value: 'text',
                    label: Text('Text'),
                    icon: Icon(Icons.text_fields, size: 16),
                  ),
                  ButtonSegment(
                    value: 'voice',
                    label: const Text('Voice'),
                    icon: const Icon(Icons.volume_up_outlined, size: 16),
                    enabled: c.welcomeAudioAvailable && v != null,
                  ),
                ],
                selected: {c.personalProfile.replyMode},
                onSelectionChanged: c.sending
                    ? null
                    : (values) => perform(context, c, () async {
                        if (values.first == 'text' &&
                            v?.stage == VoiceStage.speaking) {
                          await v?.stop();
                        }
                        await c.setReplyMode(values.first);
                      }),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              if (v != null)
                IconButton.filledTonal(
                  tooltip: capturing
                      ? 'Stop voice recording'
                      : 'Record a voice message',
                  onPressed:
                      c.sending ||
                          c.loadingConversation ||
                          transcribing ||
                          reviewing ||
                          !c.transcriptionAvailable
                      ? null
                      : () => v.recordMessage(),
                  icon: Icon(capturing ? Icons.stop : Icons.mic_none),
                ),
            ],
          ),
          if (capturing)
            Row(
              children: [
                const Icon(
                  Icons.fiber_manual_record,
                  color: Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Recording · ${v!.seconds}s / 60s')),
                TextButton(onPressed: v.stop, child: const Text('Cancel')),
              ],
            ),
          if (transcribing)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Preparing your transcript…'),
            ),
          if (v?.hasRecording == true &&
              (reviewing || v?.stage == VoiceStage.failed))
            Panel(
              color: lilac,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Your voice message',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (reviewing)
                    TextField(
                      key: const ValueKey('voice-transcript-review'),
                      controller: _transcript,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 12000,
                      decoration: const InputDecoration(
                        labelText: 'Review before sending',
                        helperText:
                            'Check names, times and any [unclear] words.',
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: v!.previewing ? null : v.replayRecording,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Replay recording'),
                      ),
                      TextButton(
                        onPressed: v.retryTranscription,
                        child: const Text('Transcribe again'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await v.stop();
                          _source = null;
                          _transcript.clear();
                        },
                        child: const Text('Discard'),
                      ),
                    ],
                  ),
                  if (reviewing)
                    FilledButton(
                      onPressed: c.sending || c.loadingConversation
                          ? null
                          : () => v.sendReviewedMessage(_transcript.text),
                      child: const Text('Send voice message'),
                    ),
                ],
              ),
            ),
          if (v?.stage == VoiceStage.speaking)
            TextButton.icon(
              onPressed: v!.stop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop voice reply'),
            ),
          if (v?.stage == VoiceStage.replying && !c.sending)
            TextButton.icon(
              onPressed: v!.stop,
              icon: const Icon(Icons.stop),
              label: const Text('Cancel voice playback'),
            ),
          if (v?.error != null)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                v!.error!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
