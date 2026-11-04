import 'dart:async';

import 'package:flutter/material.dart';

import '../app/companion_controller.dart';
import '../voice/voice_controller.dart';
import 'actions.dart';
import 'personalization.dart';
import 'theme.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    required this.controller,
    this.voice,
    required this.continueChat,
  });
  final CompanionController controller;
  final VoiceController? voice;
  final VoidCallback continueChat;
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _saving = false;
  bool _soundOff = true;
  @override
  void dispose() {
    unawaited(widget.voice?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        language = languageCode(c.personalProfile.language);
    final description = switch (language) {
      'sw' =>
        'Mimi ni ${c.companion!.name}, rafiki yako wa AI. Tunaweza kuzungumza kuhusu siku yako na mambo yanayokuhusu. Ukiruhusu kumbukumbu, nitahifadhi mambo muhimu unayoshiriki. Unaweza kuyabadilisha au kuyafuta wakati wowote.',
      'fr' =>
        'Je suis ${c.companion!.name}, ton compagnon IA. On peut parler de ta journée et de ce qui compte pour toi. Si tu actives les souvenirs, je peux garder les détails que tu partages. Tu peux les corriger ou les effacer à tout moment.',
      'es' =>
        'Soy ${c.companion!.name}, tu compañía de IA. Podemos hablar de tu día y de lo que te importa. Si activas los recuerdos, puedo guardar detalles que compartas. Puedes corregirlos o borrarlos cuando quieras.',
      'pt' =>
        'Sou ${c.companion!.name}, sua companhia de IA. Podemos conversar sobre seu dia e o que importa para você. Com sua permissão, posso guardar detalhes que você compartilhar. Você pode corrigir ou apagar esses detalhes quando quiser.',
      'ar' =>
        'أنا ${c.companion!.name}، رفيقك بالذكاء الاصطناعي. يمكننا الحديث عن يومك وما يهمك. بإذنك، يمكنني حفظ التفاصيل التي تشاركها، ويمكنك تعديلها أو حذفها في أي وقت.',
      _ =>
        'I’m ${c.companion!.name}, your AI companion. We can talk about your day and the things that matter to you. With your permission, I can keep useful details you share. You can correct or forget them any time.',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Brand(),
                  const SizedBox(height: 34),
                  const LumiOrb(size: 112),
                  const SizedBox(height: 30),
                  Text(
                    welcomeTitle(
                      c.personalProfile.preferredName ?? '',
                      c.personalProfile.language,
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 18),
                  Text(description, textAlign: TextAlign.center),
                  const SizedBox(height: 22),
                  Text(
                    _soundOff
                        ? 'Sound is off. Your welcome will not play audio automatically.'
                        : 'Welcome audio is on.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedInk),
                  ),
                  const SizedBox(height: 24),
                  if (c.welcomeAudioAvailable && widget.voice != null) ...[
                    TextButton.icon(
                      onPressed:
                          widget.voice!.stage == VoiceStage.idle ||
                              widget.voice!.stage == VoiceStage.failed
                          ? () async {
                              setState(() => _soundOff = false);
                              await widget.voice!.playWelcome();
                            }
                          : null,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Play or replay my welcome'),
                    ),
                    TextButton(
                      onPressed: () async {
                        setState(() => _soundOff = true);
                        await widget.voice!.stop();
                      },
                      child: const Text('Sound off'),
                    ),
                    if (widget.voice!.error != null)
                      Text(widget.voice!.error!.message),
                  ],
                  ActionButton(
                    label: switch (language) {
                      'sw' => 'Tuanze',
                      'fr' => 'Faisons connaissance',
                      'es' => 'Conozcámonos',
                      'pt' => 'Vamos conversar',
                      'ar' => 'لنتعارف',
                      _ => 'Let’s get to know each other',
                    },
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            try {
                              if (await perform(
                                context,
                                c,
                                c.completeWelcome,
                              )) {
                                widget.continueChat();
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
