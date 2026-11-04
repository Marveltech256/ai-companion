import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../app/companion_controller.dart';
import '../core/app_failure.dart';
import 'speech_gateway.dart';
import 'voice_hardware.dart';

enum VoiceStage {
  idle,
  permission,
  recording,
  transcribing,
  replying,
  speaking,
  review,
  failed,
}

/// Explicit microphone turns reuse the persisted text engine and its memory.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.companion,
    required this.hardware,
    required this.gateway,
  }) {
    _owner = companion.userId;
    _conversation = companion.activeConversation?.id;
    companion.addListener(_sessionChanged);
  }
  final CompanionController companion;
  final VoiceHardware hardware;
  final SpeechGateway gateway;
  VoiceStage stage = VoiceStage.idle;
  AppFailure? error;
  String caption = '';
  int seconds = 0;
  int _epoch = 0;
  bool _disposed = false;
  String? _owner;
  String? _conversation;
  Timer? _timer;
  StreamSubscription<Uint8List>? _recording;
  BytesBuilder? _bytes;
  bool _reviewMessage = false;
  Uint8List? _original;
  bool previewing = false;
  bool get hasRecording => _original != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _sessionChanged() {
    final conversation = companion.activeConversation?.id;
    final changed = conversation != _conversation;
    final ownCreation =
        stage == VoiceStage.replying &&
        _conversation == null &&
        conversation != null;
    _conversation = conversation;
    if (companion.userId != _owner ||
        companion.companion == null ||
        (!companion.companion!.voiceEnabled &&
            stage != VoiceStage.idle &&
            stage != VoiceStage.permission) ||
        (changed && !ownCreation)) {
      _owner = companion.userId;
      if (stage != VoiceStage.idle || caption.isNotEmpty) unawaited(stop());
      caption = '';
    }
  }

  String get status => switch (stage) {
    VoiceStage.idle => 'Ready when you are',
    VoiceStage.permission => 'Allow microphone access',
    VoiceStage.recording => 'Listening to your turn',
    VoiceStage.transcribing => 'Finding your words',
    VoiceStage.replying => 'A little thought',
    VoiceStage.speaking => '${companion.companion?.name ?? 'Lumi'} is speaking',
    VoiceStage.review => 'Review your voice message',
    VoiceStage.failed => 'Please try again',
  };
  Future<void> toggle() async {
    if (companion.loadingConversation) return;
    if (companion.sending && stage != VoiceStage.speaking) return;
    if (stage == VoiceStage.recording) {
      await finish();
      return;
    }
    if (stage == VoiceStage.speaking) {
      await stop();
    }
    if (stage != VoiceStage.idle && stage != VoiceStage.failed) return;
    final epoch = ++_epoch;
    stage = VoiceStage.permission;
    error = null;
    _notify();
    try {
      if (!await hardware.permission()) {
        throw const AppFailure(
          'microphone_denied',
          'Microphone access is not allowed.',
        );
      }
      if (!_current(epoch)) return;
      await companion.setVoiceEnabled(true);
      if (!_current(epoch)) return;
      final stream = await hardware.record();
      if (!_current(epoch)) {
        await hardware.stop();
        return;
      }
      _bytes = BytesBuilder(copy: true);
      seconds = 0;
      stage = VoiceStage.recording;
      _recording = stream.listen(
        (chunk) {
          if (!_current(epoch) || _bytes == null) return;
          if (_bytes!.length + chunk.length > 1920000) {
            unawaited(finish());
            return;
          }
          _bytes!.add(chunk);
        },
        onError: (Object e) {
          unawaited(_fail(e, epoch));
        },
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds++;
        if (seconds >= 60) {
          unawaited(finish());
        } else {
          _notify();
        }
      });
      _notify();
    } catch (e) {
      await _fail(e, epoch);
    }
  }

  Future<void> finish() async {
    if (stage != VoiceStage.recording) return;
    final epoch = _epoch;
    stage = VoiceStage.transcribing;
    _timer?.cancel();
    _notify();
    try {
      await hardware.finishRecording();
      await _recording?.cancel();
      _recording = null;
      if (!_current(epoch)) return;
      final pcm = _bytes?.takeBytes() ?? Uint8List(0);
      _bytes = null;
      if (pcm.length < 3200) {
        throw const AppFailure('no_speech', 'Please record a little longer.');
      }
      final wave = pcmToWave(pcm);
      if (_reviewMessage) {
        _original?.fillRange(0, _original!.length, 0);
        _original = wave;
      }
      late final String text;
      try {
        text = await gateway.transcribe(wave);
      } finally {
        if (!_reviewMessage) wave.fillRange(0, wave.length, 0);
        pcm.fillRange(0, pcm.length, 0);
      }
      if (!_current(epoch)) return;
      caption = text;
      if (_reviewMessage) {
        stage = VoiceStage.review;
        _notify();
        return;
      }
      stage = VoiceStage.replying;
      _notify();
      if (companion.sending) {
        throw const AppFailure(
          'turn_busy',
          'Please wait for the current reply.',
        );
      }
      await companion.send(text);
      if (!_current(epoch)) return;
      if (companion.error != null) throw companion.error!;
      final replies = companion.messages.where(
        (m) => m.role == 'assistant' && !m.pending && !m.failed,
      );
      if (replies.isEmpty) {
        throw const AppFailure('no_reply', 'Please try your turn again.');
      }
      final reply = replies.last;
      caption = reply.content;
      _notify();
      final clips = await gateway.speech(reply.id);
      if (!_current(epoch)) return;
      stage = VoiceStage.speaking;
      _notify();
      for (final clip in clips) {
        if (!_current(epoch)) break;
        await hardware.play(clip);
        clip.fillRange(0, clip.length, 0);
      }
      if (_current(epoch)) {
        stage = VoiceStage.idle;
        _notify();
      }
    } catch (e) {
      await _fail(e, epoch);
    }
  }

  Future<void> recordMessage() async {
    if (companion.sending ||
        companion.loadingConversation ||
        stage == VoiceStage.transcribing) {
      return;
    }
    if (stage == VoiceStage.recording) {
      await finish();
      return;
    }
    await stop();
    _reviewMessage = true;
    await toggle();
  }

  Future<void> replayRecording() async {
    final bytes = _original;
    if (bytes == null || previewing) return;
    previewing = true;
    _notify();
    try {
      await hardware.play(bytes);
    } finally {
      previewing = false;
      _notify();
    }
  }

  Future<void> retryTranscription() async {
    final bytes = _original;
    if (bytes == null) return;
    final epoch = ++_epoch;
    error = null;
    stage = VoiceStage.transcribing;
    _notify();
    try {
      final text = await gateway.transcribe(bytes);
      if (!_current(epoch)) return;
      caption = text;
      stage = VoiceStage.review;
      _notify();
    } catch (e) {
      await _fail(e, epoch);
    }
  }

  Future<void> sendReviewedMessage(String text) async {
    if (stage != VoiceStage.review ||
        text.trim().isEmpty ||
        companion.sending ||
        companion.loadingConversation) {
      return;
    }
    final epoch = _epoch;
    caption = text.trim();
    stage = VoiceStage.replying;
    error = null;
    _notify();
    try {
      await hardware.stop();
      if (!_current(epoch)) return;
      if (companion.retryContent == caption) {
        await companion.retrySend();
      } else {
        await companion.send(caption);
      }
      if (!_current(epoch)) return;
      if (companion.error != null) throw companion.error!;
      _original?.fillRange(0, _original!.length, 0);
      _original = null;
      _reviewMessage = false;
      stage = VoiceStage.idle;
      _notify();
      if (companion.personalProfile.replyMode == 'voice') await speakReply();
    } catch (e) {
      if (!_current(epoch)) return;
      error = e is AppFailure
          ? e
          : const AppFailure(
              'voice_unavailable',
              'Your voice message is still here. Please try again.',
            );
      stage = VoiceStage.review;
      _notify();
    }
  }

  Future<void> speakReply([String? messageId]) async {
    if (companion.sending || companion.loadingConversation) return;
    final messages = companion.messages.where(
      (m) =>
          m.role == 'assistant' &&
          !m.pending &&
          !m.failed &&
          (messageId == null || m.id == messageId),
    );
    if (messages.isEmpty) return;
    final epoch = ++_epoch;
    error = null;
    stage = VoiceStage.replying;
    _notify();
    List<Uint8List> clips = [];
    try {
      await companion.setVoiceEnabled(true);
      if (!_current(epoch)) return;
      clips = await gateway.speech(messages.last.id);
      if (!_current(epoch)) return;
      caption = messages.last.content;
      stage = VoiceStage.speaking;
      _notify();
      for (final clip in clips) {
        if (!_current(epoch)) break;
        await hardware.play(clip);
      }
      if (_current(epoch)) {
        stage = VoiceStage.idle;
        _notify();
      }
    } catch (e) {
      await _fail(e, epoch);
    } finally {
      for (final clip in clips) {
        clip.fillRange(0, clip.length, 0);
      }
    }
  }

  /// Leaving chat stops capture, preserving an unsent recording locally.
  Future<void> suspend() async {
    if (stage == VoiceStage.recording && _reviewMessage) {
      final epoch = ++_epoch;
      _timer?.cancel();
      stage = VoiceStage.transcribing;
      _notify();
      await hardware.finishRecording();
      await _recording?.cancel();
      _recording = null;
      if (!_current(epoch)) return;
      final pcm = _bytes?.takeBytes();
      _bytes = null;
      if (pcm != null && pcm.length >= 3200) {
        _original = pcmToWave(pcm);
        caption = '';
      }
      pcm?.fillRange(0, pcm.length, 0);
      await hardware.stop();
      if (!_current(epoch)) return;
      stage = _original == null ? VoiceStage.idle : VoiceStage.review;
      _notify();
      return;
    }
    if (_original != null) {
      await hardware.stop();
      return;
    }
    await stop();
  }

  /// User-initiated playback of a real, persisted greeting. No microphone use.
  Future<void> playWelcome() async {
    if (!companion.welcomeAudioAvailable || companion.sending) return;
    final epoch = ++_epoch;
    stage = VoiceStage.permission;
    error = null;
    _notify();
    List<Uint8List> clips = [];
    try {
      await companion.setVoiceEnabled(true);
      if (!_current(epoch)) return;
      stage = VoiceStage.replying;
      await companion.ensureGreeting();
      if (!_current(epoch)) return;
      if (companion.error != null) throw companion.error!;
      final greetings = companion.messages.where(
        (m) =>
            m.role == 'assistant' &&
            m.turnKind == 'greeting' &&
            !m.pending &&
            !m.failed,
      );
      if (greetings.isEmpty) {
        throw const AppFailure('no_greeting', 'Please try your welcome again.');
      }
      caption = greetings.first.content;
      clips = await gateway.speech(greetings.first.id);
      if (!_current(epoch)) return;
      stage = VoiceStage.speaking;
      _notify();
      for (final clip in clips) {
        if (!_current(epoch)) break;
        await hardware.play(clip);
      }
      if (_current(epoch)) {
        stage = VoiceStage.idle;
        _notify();
      }
    } catch (e) {
      await _fail(e, epoch);
    } finally {
      for (final clip in clips) {
        clip.fillRange(0, clip.length, 0);
      }
    }
  }

  Future<void> _fail(Object e, int epoch) async {
    if (!_current(epoch)) return;
    _timer?.cancel();
    await _recording?.cancel();
    _recording = null;
    _bytes = null;
    await hardware.stop();
    if (!_current(epoch)) return;
    error = e is AppFailure
        ? e
        : const AppFailure(
            'voice_unavailable',
            'Voice interrupted. Please try again.',
          );
    stage = VoiceStage.failed;
    _notify();
  }

  Future<void> stop() async {
    _epoch++;
    _timer?.cancel();
    await _recording?.cancel();
    _recording = null;
    _bytes = null;
    _original?.fillRange(0, _original!.length, 0);
    _original = null;
    _reviewMessage = false;
    await hardware.stop();
    stage = VoiceStage.idle;
    seconds = 0;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _recording?.cancel();
    companion.removeListener(_sessionChanged);
    gateway.close();
    unawaited(hardware.dispose());
    super.dispose();
  }
}

Uint8List pcmToWave(Uint8List pcm) {
  if (pcm.length > 1920000 || pcm.length.isOdd) {
    throw const AppFailure('invalid_audio', 'Please try recording again.');
  }
  final result = Uint8List(44 + pcm.length), data = ByteData(44 + pcm.length);
  void marker(int at, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(at + i, value.codeUnitAt(i));
    }
  }

  marker(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length, Endian.little);
  marker(8, 'WAVE');
  marker(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  marker(36, 'data');
  data.setUint32(40, pcm.length, Endian.little);
  result.setAll(0, data.buffer.asUint8List());
  result.setAll(44, pcm);
  return result;
}
