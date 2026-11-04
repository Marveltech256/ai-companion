import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

import 'temp_audio_stub.dart'
    if (dart.library.io) 'temp_audio_io.dart'
    as temporary;

abstract interface class VoiceHardware {
  Future<bool> permission();
  Future<Stream<Uint8List>> record();
  Future<void> finishRecording();
  Future<void> stop();
  Future<void> play(Uint8List bytes);
  Future<void> dispose();
}

class DeviceVoiceHardware implements VoiceHardware {
  DeviceVoiceHardware() {
    _prepared = temporary.cleanupSpeech();
  }
  final _recorder = AudioRecorder();
  AudioPlayer? _player;
  final _releases = Expando<Future<void>>();
  int _epoch = 0;
  Future<void> _release(AudioPlayer player) =>
      _releases[player] ??= player.dispose();
  Completer<void>? _playback;
  late final Future<void> _prepared;
  @override
  Future<bool> permission() => _recorder.hasPermission();
  @override
  Future<Stream<Uint8List>> record() async {
    final epoch = _epoch;
    await _prepared;
    if (epoch != _epoch) return const Stream.empty();
    var adjusted = false;
    await _recorder.setOnConfigChanged((config) {
      adjusted =
          config.sampleRate != 16000 ||
          config.numChannels != 1 ||
          config.encoder != AudioEncoder.pcm16bits;
    });
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    if (epoch != _epoch) {
      await _recorder.cancel();
      return const Stream.empty();
    }
    return stream.map((chunk) {
      if (adjusted) {
        throw StateError('Microphone format could not be configured.');
      }
      return chunk;
    });
  }

  @override
  Future<void> finishRecording() async {
    await _recorder.stop();
  }

  @override
  Future<void> play(Uint8List bytes) async {
    final mime =
        bytes.length >= 12 && String.fromCharCodes(bytes.take(4)) == 'RIFF'
        ? 'audio/wav'
        : 'audio/mpeg';
    final epoch = _epoch;
    final file = await temporary.writeSpeech(bytes);
    if (epoch != _epoch) {
      if (file != null) await temporary.removeSpeech(file);
      return;
    }
    final player = AudioPlayer();
    _player = player;
    final completed = Completer<void>();
    _playback = completed;
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completed.isCompleted) completed.complete();
    });
    try {
      await player.play(
        file == null
            ? BytesSource(bytes, mimeType: mime)
            : DeviceFileSource(file, mimeType: mime),
      );
      if (epoch == _epoch) {
        await completed.future.timeout(const Duration(minutes: 4));
      }
    } finally {
      await subscription.cancel();
      await _release(player);
      if (identical(_player, player)) _player = null;
      if (file != null) await temporary.removeSpeech(file);
      if (identical(_playback, completed)) _playback = null;
    }
  }

  @override
  Future<void> stop() async {
    _epoch++;
    if (_playback?.isCompleted == false) _playback!.complete();
    await _recorder.cancel();
    final player = _player;
    _player = null;
    if (player != null) await _release(player);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await temporary.cleanupSpeech();
  }
}
