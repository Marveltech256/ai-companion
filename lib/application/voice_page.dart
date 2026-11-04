import 'package:flutter/material.dart';

import '../voice/voice_controller.dart';
import 'theme.dart';

class VoicePage extends StatefulWidget {
  const VoicePage({
    super.key,
    required this.name,
    required this.voice,
    required this.end,
    required this.connect,
  });
  final String name;
  final VoiceController? voice;
  final VoidCallback end, connect;
  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  bool captions = true;
  @override
  Widget build(BuildContext context) {
    final voice = widget.voice;
    final recording = voice?.stage == VoiceStage.recording;
    final busy =
        voice != null &&
        ![
          VoiceStage.idle,
          VoiceStage.failed,
          VoiceStage.recording,
          VoiceStage.speaking,
        ].contains(voice.stage);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Return to conversation',
                    onPressed: widget.end,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  Expanded(
                    child: Text(
                      'VOICE WITH ${widget.name.toUpperCase()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: mutedInk,
                        fontSize: 11,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          voice == null
                              ? 'Connect your account to begin'
                              : recording
                              ? 'Listening · ${voice.seconds}s'
                              : voice.status,
                          style: const TextStyle(color: mutedInk),
                        ),
                        const SizedBox(height: 40),
                        LumiOrb(
                          size: 180,
                          active:
                              recording || voice?.stage == VoiceStage.speaking,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          widget.name,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 20),
                        const Icon(
                          Icons.graphic_eq,
                          color: Color(0xFFB69BCE),
                          size: 37,
                        ),
                        const SizedBox(height: 20),
                        if (captions)
                          Text(
                            voice?.caption.isNotEmpty == true
                                ? voice!.caption
                                : voice == null
                                ? 'AI voice is available with a connected account.'
                                : 'Unmute when you are ready to talk.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        if (voice?.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                voice!.error!.message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        if (voice == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: FilledButton(
                              onPressed: widget.connect,
                              child: const Text('Connect account'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _VoiceButton(
                    label: recording ? 'Mute' : 'Unmute',
                    icon: recording ? Icons.mic : Icons.mic_off_outlined,
                    onPressed: voice == null || busy
                        ? null
                        : () => voice.toggle(),
                  ),
                  _VoiceButton(
                    label: 'End',
                    icon: Icons.call_end_outlined,
                    primary: true,
                    onPressed: widget.end,
                  ),
                  _VoiceButton(
                    label: 'Captions',
                    icon: captions
                        ? Icons.closed_caption
                        : Icons.closed_caption_off_outlined,
                    onPressed: () => setState(() => captions = !captions),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text(
                'AI voice · OpenAI · Transcripts saved in history',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedInk, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filled(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          minimumSize: Size.square(primary ? 64 : 54),
          backgroundColor: primary ? plum : lilac,
          foregroundColor: primary ? Colors.white : plum,
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: mutedInk, fontSize: 11)),
    ],
  );
}
