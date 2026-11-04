import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/companion_controller.dart';
import 'package:ai_companion/voice/voice_controller.dart';
import 'package:ai_companion/data/models.dart';
import 'package:ai_companion/core/app_failure.dart';

import 'support/test_services.dart';
import 'support/voice_services.dart';

class _RetrySpeech extends TestSpeechGateway {
  bool failed = false;
  @override
  Future<String> transcribe(Uint8List wave) async {
    if (!failed) {
      failed = true;
      throw const AppFailure('voice_unavailable', 'Try again.');
    }
    return super.transcribe(wave);
  }
}

void main() {
  test('voice messages wait for transcript review and send edited words with a text reply', () async {
    final session = TestSession(), api = TestApi();
    final c = CompanionController(session: session, api: api);
    await c.restore();
    final hardware = TestVoiceHardware(),
        speech = TestSpeechGateway(),
        v = VoiceController(companion: c, hardware: hardware, gateway: speech);
    await v.recordMessage();
    hardware.chunks.add(Uint8List(6400));
    await Future<void>.delayed(Duration.zero);
    await v.finish();
    expect(v.stage, VoiceStage.review);
    expect(v.hasRecording, true);
    expect(api.turnIds, isEmpty);
    expect(speech.spoken, isEmpty);
    await v.replayRecording();
    expect(hardware.plays, 1);
    c.loadingConversation = true;
    await v.sendReviewedMessage('I enjoy cycling, not running.');
    expect(v.hasRecording, true);
    expect(api.turnIds, isEmpty);
    c.loadingConversation = false;
    await v.sendReviewedMessage('I enjoy cycling, not running.');
    expect(
      c.messages.firstWhere((m) => m.role == 'user').content,
      'I enjoy cycling, not running.',
    );
    expect(speech.spoken, isEmpty);
    expect(v.hasRecording, false);
    v.dispose();
    c.dispose();
    await session.events.close();
  });
  test(
    'selected voice replies speak the saved answer while keeping its text',
    () async {
      final session = TestSession(), api = TestApi();
      final c = CompanionController(session: session, api: api);
      await c.restore();
      await c.setReplyMode('voice');
      final hardware = TestVoiceHardware(),
          speech = TestSpeechGateway(),
          v = VoiceController(
            companion: c,
            hardware: hardware,
            gateway: speech,
          );
      await v.recordMessage();
      hardware.chunks.add(Uint8List(6400));
      await Future<void>.delayed(Duration.zero);
      await v.finish();
      await v.sendReviewedMessage('I enjoy cycling.');
      expect(v.error, isNull);
      expect(speech.spoken.last, c.messages.last.id);
      expect(c.messages.last.content, isNotEmpty);
      expect(hardware.plays, 1);
      v.dispose();
      c.dispose();
      await session.events.close();
    },
  );
  test('leaving chat stops recording and preserves the local clip without uploading it', () async {
    final session = TestSession(), api = TestApi();
    final c = CompanionController(session: session, api: api);
    await c.restore();
    final hardware = TestVoiceHardware(),
        speech = TestSpeechGateway(),
        v = VoiceController(companion: c, hardware: hardware, gateway: speech);
    await v.recordMessage();
    hardware.chunks.add(Uint8List(6400));
    await Future<void>.delayed(Duration.zero);
    await v.suspend();
    expect(v.stage, VoiceStage.review);
    expect(v.hasRecording, true);
    expect(speech.received, isNull);
    expect(api.turnIds, isEmpty);
    await v.retryTranscription();
    expect(v.caption, 'I enjoy cycling.');
    session.switchUser('bobby');
    await Future<void>.delayed(Duration.zero);
    expect(v.hasRecording, false);
    v.dispose();
    c.dispose();
    await session.events.close();
  });
  test(
    'failed recognition retains the original clip for retry or discard',
    () async {
      final session = TestSession(), api = TestApi();
      final c = CompanionController(session: session, api: api);
      await c.restore();
      final hardware = TestVoiceHardware(),
          speech = _RetrySpeech(),
          v = VoiceController(
            companion: c,
            hardware: hardware,
            gateway: speech,
          );
      await v.recordMessage();
      hardware.chunks.add(Uint8List(6400));
      await Future<void>.delayed(Duration.zero);
      await v.finish();
      expect(v.stage, VoiceStage.failed);
      expect(v.hasRecording, true);
      expect(api.turnIds, isEmpty);
      await v.retryTranscription();
      expect(v.stage, VoiceStage.review);
      expect(v.error, isNull);
      await v.stop();
      expect(v.hasRecording, false);
      v.dispose();
      c.dispose();
      await session.events.close();
    },
  );
  test('optional welcome audio replays its persisted greeting without microphone capture', () async {
    final session = TestSession(), api = TestApi();
    final companion = CompanionController(session: session, api: api);
    await companion.restore();
    companion.welcomeAudioAvailable = true;
    final hardware = TestVoiceHardware(), speech = TestSpeechGateway();
    final voice = VoiceController(
      companion: companion,
      hardware: hardware,
      gateway: speech,
    );
    expect(hardware.plays, 0);
    await voice.playWelcome();
    expect(voice.error, isNull);
    expect(hardware.plays, 1);
    expect(hardware.permissionRequests, 0);
    final greeting = companion.messages.single;
    expect(greeting.turnKind, 'greeting');
    expect(speech.spoken.single, greeting.id);
    await voice.playWelcome();
    expect(speech.spoken, [greeting.id, greeting.id]);
    expect(api.greetingIds, hasLength(1));
    expect(hardware.permissionRequests, 0);
    voice.dispose();
    companion.dispose();
    await session.events.close();
  });
  test('unmuting during speech interrupts playback and starts a new microphone turn', () async {
    final session = TestSession(), api = TestApi();
    final companion = CompanionController(session: session, api: api);
    await companion.restore();
    final hardware = TestVoiceHardware()..playback = Completer<void>();
    final voice = VoiceController(
      companion: companion,
      hardware: hardware,
      gateway: TestSpeechGateway(),
    );
    await voice.toggle();
    hardware.chunks.add(Uint8List(6400));
    await Future<void>.delayed(Duration.zero);
    final first = voice.finish();
    while (hardware.plays == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(voice.stage, VoiceStage.speaking);
    await voice.toggle();
    await first;
    expect(voice.stage, VoiceStage.recording);
    expect(hardware.stops, greaterThan(0));
    await voice.stop();
    voice.dispose();
    companion.dispose();
    await session.events.close();
  });
  test('microphone denial never uploads audio or enables voice', () async {
    final session = TestSession(), api = TestApi();
    final companion = CompanionController(session: session, api: api);
    await companion.restore();
    final hardware = TestVoiceHardware()..allowed = false;
    final speech = TestSpeechGateway();
    final voice = VoiceController(
      companion: companion,
      hardware: hardware,
      gateway: speech,
    );
    await voice.toggle();
    expect(voice.stage, VoiceStage.failed);
    expect(voice.error?.code, 'microphone_denied');
    expect(speech.received, isNull);
    expect(companion.companion!.voiceEnabled, isFalse);
    voice.dispose();
    companion.dispose();
    await session.events.close();
  });
  test('voice uses the persisted text engine and speaks its saved assistant message', () async {
    final session = TestSession(), api = TestApi();
    final companion = CompanionController(session: session, api: api);
    await companion.restore();
    final hardware = TestVoiceHardware(), speech = TestSpeechGateway();
    final voice = VoiceController(
      companion: companion,
      hardware: hardware,
      gateway: speech,
    );
    expect(hardware.permissionRequests, 0);
    await voice.toggle();
    hardware.chunks.add(Uint8List(6400));
    await Future<void>.delayed(Duration.zero);
    await voice.finish();
    expect(companion.messages.first.content, 'I enjoy cycling.');
    expect(voice.caption, 'What do you enjoy about cycling?');
    expect(speech.spoken, ['assistant']);
    expect(hardware.plays, 1);
    expect(voice.stage, VoiceStage.idle);
    expect(
      ByteData.sublistView(speech.received!).getUint32(24, Endian.little),
      16000,
    );
    expect(companion.companion!.voiceEnabled, isTrue);
    voice.dispose();
    companion.dispose();
    await session.events.close();
  });
  test(
    'an account change during transcription cannot send or speak the old audio',
    () async {
      final session = TestSession(), api = TestApi();
      final companion = CompanionController(session: session, api: api);
      await companion.restore();
      final hardware = TestVoiceHardware(), speech = TestSpeechGateway();
      speech.pending = Completer<String>();
      final voice = VoiceController(
        companion: companion,
        hardware: hardware,
        gateway: speech,
      );
      await voice.toggle();
      hardware.chunks.add(Uint8List(6400));
      await Future<void>.delayed(Duration.zero);
      final finishing = voice.finish();
      while (speech.received == null) {
        await Future<void>.delayed(Duration.zero);
      }
      session.switchUser('bob');
      speech.pending!.complete('Private old-account words');
      await finishing;
      expect(api.turnIds, isEmpty);
      expect(speech.spoken, isEmpty);
      expect(voice.caption, isEmpty);
      expect(hardware.stops, greaterThan(0));
      voice.dispose();
      companion.dispose();
      await session.events.close();
    },
  );
  test('revoking voice consent stops an active microphone turn', () async {
    final session = TestSession(), api = TestApi();
    final companion = CompanionController(session: session, api: api);
    await companion.restore();
    final hardware = TestVoiceHardware(), speech = TestSpeechGateway();
    final voice = VoiceController(
      companion: companion,
      hardware: hardware,
      gateway: speech,
    );
    await voice.toggle();
    expect(voice.stage, VoiceStage.recording);
    await companion.setVoiceEnabled(false);
    await Future<void>.delayed(Duration.zero);
    expect(voice.stage, VoiceStage.idle);
    expect(speech.received, isNull);
    expect(hardware.stops, greaterThan(0));
    voice.dispose();
    companion.dispose();
    await session.events.close();
  });
  test(
    'changing conversation stops capture instead of sending to the new history',
    () async {
      final session = TestSession(), api = TestApi();
      final companion = CompanionController(session: session, api: api);
      await companion.restore();
      await companion.openConversation(
        const Conversation(id: 'first', title: 'First'),
      );
      final hardware = TestVoiceHardware(), speech = TestSpeechGateway();
      final voice = VoiceController(
        companion: companion,
        hardware: hardware,
        gateway: speech,
      );
      await voice.toggle();
      await companion.openConversation(
        const Conversation(id: 'second', title: 'Second'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(voice.stage, VoiceStage.idle);
      expect(speech.received, isNull);
      expect(hardware.stops, greaterThan(0));
      voice.dispose();
      companion.dispose();
      await session.events.close();
    },
  );
}
